#!/usr/bin/env python3
"""Operator-triggered, strict-host-key SFTP aggregation for Xray-script.

No provider HTTP polling, timers, remote pushes, or changes to Xray configuration.
The center keeps last verified local peer snapshots and publishes static subscriptions.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

from clash_multi import NAME_RE, PROXY_MARKER, GROUP_MARKER, RULE_MARKER, TEST_URL, atomic_json, atomic_text, quote
from clash_shadowrocket import MAX_PROVIDER_BYTES, make_uri, parse_provider, validate_node

HOST = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.:-]{0,252}$")
USER = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
REMOTE = re.compile(r"^/[A-Za-z0-9_.\/-]+/proxies\.yaml$")
BOOL_KEYS = {"tls", "udp", "skip-cert-verify", "support-x25519mlkem768"}
MAX_PEERS = 20


def load(path):
    if not path.exists():
        return {"enabled": False, "nodes": []}
    config = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(config, dict) or not isinstance(config.get("enabled"), bool):
        raise ValueError("Invalid SSH center config")
    nodes = config.get("nodes")
    if not isinstance(nodes, list) or len(nodes) > MAX_PEERS:
        raise ValueError("Invalid SSH node list")
    result, names = [], set()
    for item in nodes:
        peer = validate_peer(item)
        if peer["name"] in names:
            raise ValueError("Duplicate SSH peer name")
        names.add(peer["name"])
        result.append(peer)
    return {"enabled": config["enabled"], "nodes": result}


def validate_peer(peer):
    if not isinstance(peer, dict):
        raise ValueError("Invalid SSH peer")
    name, host, user = (peer.get(k) for k in ("name", "host", "user"))
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        raise ValueError("Invalid peer label")
    if not isinstance(host, str) or not HOST.fullmatch(host) or ".." in host:
        raise ValueError("Invalid peer host")
    if not isinstance(user, str) or not USER.fullmatch(user):
        raise ValueError("Invalid SSH username")
    try:
        port = int(peer.get("port", 22))
    except (ValueError, TypeError) as exc:
        raise ValueError("Invalid SSH port") from exc
    if not 1 <= port <= 65535:
        raise ValueError("Invalid SSH port")
    remote = peer.get("remote_path", "/root/.xray-script/clash/proxies.yaml")
    if not isinstance(remote, str) or not REMOTE.fullmatch(remote) or "/../" in remote or "/./" in remote:
        raise ValueError("Remote file must be an absolute proxies.yaml path without spaces or traversal")
    result = {"name": name, "host": host, "port": port, "user": user, "remote_path": remote}
    for field in ("key_file", "known_hosts"):
        value = peer.get(field)
        if not isinstance(value, str) or not value.startswith("/") or "\n" in value:
            raise ValueError("An absolute " + field + " is required")
        p = Path(value)
        if ".." in p.parts or not p.is_file() or p.is_symlink():
            raise ValueError(field + " must be an existing regular file")
        result[field] = value
    key = Path(result["key_file"])
    if key.stat().st_mode & 0o077:
        raise ValueError("SSH key must not be group/world accessible (chmod 600)")
    return result


def edit(path, operation, peer=None, name=None):
    config = load(path)
    if operation == "enable":
        config["enabled"] = True
    elif operation == "disable":
        config["enabled"] = False
    elif operation == "add":
        item = validate_peer(peer)
        config["nodes"] = [p for p in config["nodes"] if p["name"] != item["name"]]
        if len(config["nodes"]) >= MAX_PEERS:
            raise ValueError("Too many peers")
        config["nodes"].append(item)
    elif operation == "remove":
        if name not in [p["name"] for p in config["nodes"]]:
            raise ValueError("Peer not configured")
        config["nodes"] = [p for p in config["nodes"] if p["name"] != name]
    atomic_json(path, config)
    return config


def sftp_fetch(peer, directory, runner=subprocess.run):
    """Use SFTP, not shell commands or HTTP. Strict known_hosts, private key, no prompts."""
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    fd, candidate = tempfile.mkstemp(prefix=".sftp-", dir=directory)
    os.close(fd)
    try:
        command = [
            "sftp", "-q", "-b", "-", "-P", str(peer["port"]), "-i", peer["key_file"],
            "-oBatchMode=yes", "-oIdentitiesOnly=yes", "-oStrictHostKeyChecking=yes",
            "-oUserKnownHostsFile=" + peer["known_hosts"], "-oConnectTimeout=8",
            "-oNumberOfPasswordPrompts=0", "-oLogLevel=ERROR",
            peer["user"] + "@" + peer["host"],
        ]
        # validate_peer permits no spaces/quotes/metacharacters in the remote path.
        cmd_input = "get " + peer["remote_path"] + " " + candidate + "\n"
        try:
            result = runner(command, input=cmd_input, capture_output=True, text=True, timeout=25)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError("SFTP transport unavailable or timed out") from exc
        if result.returncode:
            # Never echo remote stderr (could contain user paths or sensitive data).
            raise ValueError("SFTP failed: check SSH port, authorized key, pinned host key and file permissions")
        data = Path(candidate).read_bytes()
        if len(data) > MAX_PROVIDER_BYTES:
            raise ValueError("Remote proxies.yaml exceeds size limit")
        try:
            content = data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError("Remote proxies.yaml is not UTF-8") from exc
        nodes = parse_provider(content)
        for node in nodes:
            validate_node(node)
        return content
    finally:
        Path(candidate).unlink(missing_ok=True)


def cache_file(directory, name):
    if not NAME_RE.fullmatch(name):
        raise ValueError("Invalid cache name")
    return directory / (name + ".yaml")


def scalar(key, value):
    if key == "port":
        return str(int(value))
    if key in BOOL_KEYS:
        if str(value).lower() not in ("true", "false"):
            raise ValueError("Invalid YAML boolean " + key)
        return str(value).lower()
    return quote(str(value))


def render_proxy(node, name):
    lines = ["  - name: " + quote(name)]
    for key, value in node.items():
        if key == "name":
            continue
        if isinstance(value, dict):
            lines.append("    " + key + ":")
            for subkey, subval in value.items():
                lines.append("      " + subkey + ": " + scalar(subkey, subval))
        elif isinstance(value, list):
            lines.append("    " + key + ":")
            lines.extend("      - " + quote(str(v)) for v in value)
        else:
            lines.append("    " + key + ": " + scalar(key, value))
    return "\n".join(lines)


def merge(local_single, local_provider, cached):
    """Build full Mihomo/Shadowrocket from one validated point-in-time view."""
    if any(local_single.count(s) != 1 for s in (PROXY_MARKER, GROUP_MARKER, RULE_MARKER)):
        raise ValueError("Standalone YAML sections not recognized")
    local_nodes = parse_provider(local_provider)
    for node in local_nodes:
        validate_node(node)
    before = local_single.split(GROUP_MARKER, 1)[0].split(PROXY_MARKER, 1)[0]
    routing = local_single.split(RULE_MARKER, 1)[1]
    entries, seen, dedup = [], set(), set()
    for prefix, nodes in [("Local", local_nodes)] + cached:
        for node in nodes:
            validate_node(node)
            label = prefix + "-" + node["name"]
            fingerprint = (node.get("type"), node.get("server"), node.get("port"),
                           node.get("uuid"), node.get("network", "tcp"), node.get("flow"),
                           node.get("servername"), json.dumps(node.get("reality-opts"), sort_keys=True))
            if fingerprint in dedup:
                continue
            if label in seen:
                raise ValueError("Duplicate node name in subscription")
            seen.add(label)
            dedup.add(fingerprint)
            entries.append((label, node))
    if not entries:
        raise ValueError("No valid subscription nodes")
    names = [name for name, _ in entries]
    out = [before.rstrip(), "", "proxies:"]
    out.extend(render_proxy(node, name) for name, node in entries)
    out.extend(["", "proxy-groups:"])
    for label, kind, choices in (
        ("Proxy", "select", ["Auto", "Failover", "Balance"] + names + ["DIRECT"]),
        ("Auto", "url-test", names),
        ("Failover", "fallback", names),
        ("Balance", "load-balance", names),
    ):
        out += ["  - name: " + quote(label), "    type: " + kind, "    proxies:"]
        out += ["      - " + quote(choice) for choice in choices]
        if kind != "select":
            out += ["    url: " + quote(TEST_URL), "    interval: 300", "    lazy: true",
                    "    expected-status: 204"]
            if kind == "url-test":
                out.append("    tolerance: 50")
            if kind == "load-balance":
                out.append("    strategy: consistent-hashing")
    yaml_text = "\n".join(out) + RULE_MARKER + routing
    uri_text = "\n".join(make_uri(node, name) for name, node in entries) + "\n"
    return yaml_text, base64.b64encode(uri_text.encode("utf-8"))


def publish(config, single, local, directory, multi, shadowrocket, updates=None):
    if not config["enabled"]:
        raise ValueError("SSH center not enabled")
    updates = updates or {}
    cached = []
    for peer in config["nodes"]:
        if peer["name"] in updates:
            raw = updates[peer["name"]]
        else:
            path = cache_file(directory, peer["name"])
            if not path.exists():
                continue  # Newly added peer is not included until its first successful sync.
            raw = path.read_text(encoding="utf-8")
        nodes = parse_provider(raw)
        for n in nodes:
            validate_node(n)
        cached.append((peer["name"], nodes))
    yaml_text, text64 = merge(single.read_text(encoding="utf-8"),
                              local.read_text(encoding="utf-8"), cached)
    # Validate all outputs *before* replacing any publication or cache.
    for name, content in updates.items():
        atomic_text(cache_file(directory, name), content)
    atomic_text(multi, yaml_text)
    atomic_bytes(shadowrocket, text64)
    return sum(len(n) for _, n in cached)


def atomic_bytes(path, data):
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", type=Path, required=True)
    p.add_argument("--single", type=Path)
    p.add_argument("--local", type=Path)
    p.add_argument("--cache-dir", type=Path)
    p.add_argument("--multi", type=Path)
    p.add_argument("--shadowrocket", type=Path)
    sub = p.add_subparsers(dest="command", required=True)
    for op in ("enable", "disable", "list", "render"):
        sub.add_parser(op)
    add = sub.add_parser("add")
    for key in ("name", "host", "user", "remote_path", "key_file", "known_hosts"):
        add.add_argument(key)
    add.add_argument("--port", type=int, default=22)
    for op in ("remove", "test"):
        sub.add_parser(op).add_argument("name")
    sync = sub.add_parser("sync")
    sync.add_argument("name", nargs="?", default="all")
    args = p.parse_args()
    try:
        if args.command in ("enable", "disable", "add", "remove"):
            peer = None
            if args.command == "add":
                peer = {key: getattr(args, key) for key in (
                    "name", "host", "user", "remote_path", "key_file", "known_hosts")}
                peer["port"] = args.port
            edit(args.config, args.command, peer, getattr(args, "name", None))
            print("Configuration saved; existing Xray and remote subscription are unchanged.")
            return 0
        config = load(args.config)
        if args.command == "list":
            for node in config["nodes"]:
                cached = cache_file(args.cache_dir, node["name"]) if args.cache_dir else None
                stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(cached.stat().st_mtime)) if cached and cached.exists() else "never"
                print(f"{node['name']} {node['user']}@{node['host']}:{node['port']} last-valid={stamp}")
            return 0
        if not config["enabled"]:
            raise ValueError("SSH center not enabled")
        nodes = [peer for peer in config["nodes"] if args.command == "render" or
                 getattr(args, "name", "all") in ("all", peer["name"])]
        if args.command != "render" and not nodes:
            raise ValueError("Peer not found")
        if args.command == "test":
            sftp_fetch(nodes[0], args.cache_dir)
            print("SFTP connection, host key and provider verification: PASS")
            return 0
        updates, failures = {}, []
        if args.command == "sync":
            for node in nodes:
                try:
                    updates[node["name"]] = sftp_fetch(node, args.cache_dir)
                    print(node["name"] + ": verified")
                except (ValueError, OSError) as exc:
                    failures.append(node["name"] + ": " + str(exc))
        count = publish(config, args.single, args.local, args.cache_dir, args.multi,
                        args.shadowrocket, updates)
        print("Published static subscriptions; cached remote nodes:", count)
        for failure in failures:
            print("SYNC FAILED (last valid cache retained): " + failure)
        return 1 if failures else 0
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        p.exit(1, "ssh-center: " + str(exc) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
