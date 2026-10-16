#!/usr/bin/env python3
"""Build opt-in Mihomo multi-server subscriptions from the existing single-server YAML.

Only the generated Clash YAML is read: this helper never modifies Xray's configuration.
It uses the YAML layout emitted by core/clash.sh and only the Python standard library.
"""
import argparse
import json
import os
import re
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,31}$")
NODE_RE = re.compile(r"(?m)^  - name: '((?:[^']|'')*)'$")
PROVIDER_PATH_RE = re.compile(r"^/sub/[A-Za-z0-9_-]{16,128}/proxies\.yaml$")
PROXY_MARKER = "\n# =========================\n# Proxies\n# =========================\nproxies:\n"
GROUP_MARKER = "\n# =========================\n# Proxy groups\n# =========================\nproxy-groups:\n"
RULE_MARKER = "\n# =========================\n# Routing rules\n# =========================\nrules:\n"
TEST_URL = "https://www.gstatic.com/generate_204"


def quote(value):
    # JSON string syntax is a subset of YAML double-quoted scalar syntax.
    return json.dumps(value, ensure_ascii=True)


def validate_peer(peer):
    if not isinstance(peer, dict):
        raise ValueError("Peer must be an object")
    name, url = peer.get("name"), peer.get("url")
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        raise ValueError("Peer name must match [A-Za-z][A-Za-z0-9_-]{0,31}")
    if not isinstance(url, str) or any(ch.isspace() for ch in url):
        raise ValueError("Invalid peer Provider URL")
    parsed = urlsplit(url)
    if (
        parsed.scheme not in ("http", "https")
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or parsed.query
        or not PROVIDER_PATH_RE.fullmatch(parsed.path)
    ):
        raise ValueError("Peer URL must be an HTTP(S) /sub/<provider-token>/proxies.yaml URL")
    try:
        _ = parsed.port
    except ValueError as exc:
        raise ValueError("Invalid peer URL port") from exc
    return {"name": name, "url": url}


def validated_config(value):
    if not isinstance(value, dict) or not isinstance(value.get("enabled"), bool):
        raise ValueError("Configuration requires boolean 'enabled'")
    peers = value.get("peers")
    if not isinstance(peers, list):
        raise ValueError("Configuration requires a 'peers' list")
    seen_names, seen_urls = set(), set()
    normalized = []
    for peer in peers:
        item = validate_peer(peer)
        if item["name"] in seen_names or item["url"] in seen_urls:
            raise ValueError("Duplicate peer name or URL")
        seen_names.add(item["name"])
        seen_urls.add(item["url"])
        normalized.append(item)
    return {"enabled": value["enabled"], "peers": normalized}


def load_config(path):
    if not path.exists():
        return {"enabled": False, "peers": []}
    return validated_config(json.loads(path.read_text(encoding="utf-8")))


def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def atomic_json(path, value):
    atomic_text(path, json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def edit_config(path, operation, name=None, url=None):
    config = load_config(path)
    if operation == "add":
        peer = validate_peer({"name": name, "url": url})
        config["peers"] = [p for p in config["peers"] if p["name"] != peer["name"]]
        if any(p["url"] == peer["url"] for p in config["peers"]):
            raise ValueError("Another peer already has this URL")
        config["peers"].append(peer)
    elif operation == "remove":
        if not any(p["name"] == name for p in config["peers"]):
            raise ValueError("Peer not found: " + name)
        config["peers"] = [p for p in config["peers"] if p["name"] != name]
    elif operation == "enable":
        config["enabled"] = True
    elif operation == "disable":
        config["enabled"] = False
    validated_config(config)
    atomic_json(path, config)
    return config


def render_group(name, kind, nodes, peers, extras=""):
    lines = ["  - name: " + quote(name), "    type: " + kind]
    if extras:
        lines.extend("    " + entry for entry in extras.split("\n"))
    if nodes or name == "Proxy":
        lines.append("    proxies:")
        lines.extend("      - " + quote(node) for node in nodes)
    if peers:
        lines.append("    use:")
        lines.extend("      - " + quote(peer["name"]) for peer in peers)
    return "\n".join(lines) + "\n"


def render_files(single_yaml, peers):
    if single_yaml.count(PROXY_MARKER) != 1 or single_yaml.count(GROUP_MARKER) != 1 or single_yaml.count(RULE_MARKER) != 1:
        raise ValueError("The single subscription does not have the expected Xray-script sections")
    before_groups, rest = single_yaml.split(GROUP_MARKER, 1)
    _, routing = rest.split(RULE_MARKER, 1)
    proxy_body = before_groups.split(PROXY_MARKER, 1)[1]
    nodes = [match.replace("''", "'") for match in NODE_RE.findall(proxy_body)]
    if not nodes:
        raise ValueError("No local proxy nodes were found")
    provider_yaml = "proxies:\n" + proxy_body.strip("\n") + "\n"

    provider_lines = []
    if peers:
        provider_lines.append("proxy-providers:")
        for peer in peers:
            name = peer["name"]
            provider_lines.extend([
                "  " + quote(name) + ":",
                "    type: http",
                "    url: " + quote(peer["url"]),
                "    interval: 300",
                "    proxy: DIRECT",
                "    health-check:",
                "      enable: true",
                "      url: " + quote(TEST_URL),
                "      interval: 300",
                "      expected-status: 204",
                "    override:",
                "      additional-prefix: " + quote(name + "-"),
            ])
        provider_lines.append("")

    proxy_group = render_group("Proxy", "select",
                               ["Auto", "Failover", "Balance"] + nodes + ["DIRECT"], peers)
    auto_group = render_group("Auto", "url-test", nodes, peers,
                              "url: " + quote(TEST_URL) + "\ninterval: 300\ntolerance: 50\nlazy: true\nexpected-status: 204")
    fail_group = render_group("Failover", "fallback", nodes, peers,
                              "url: " + quote(TEST_URL) + "\ninterval: 300\nlazy: true\nexpected-status: 204")
    balance_group = render_group("Balance", "load-balance", nodes, peers,
                                 "strategy: consistent-hashing\nurl: " + quote(TEST_URL) + "\ninterval: 300\nlazy: true\nexpected-status: 204")
    multi_yaml = (
        before_groups.rstrip("\n") + "\n\n"
        + "\n".join(provider_lines)
        + "proxy-groups:\n" + proxy_group + "\n" + auto_group + "\n"
        + fail_group + "\n" + balance_group
        + RULE_MARKER + routing
    )
    return provider_yaml, multi_yaml


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    generate = sub.add_parser("generate")
    generate.add_argument("--single", type=Path, required=True)
    generate.add_argument("--provider", type=Path, required=True)
    generate.add_argument("--multi", type=Path, required=True)
    add = sub.add_parser("add")
    add.add_argument("name")
    add.add_argument("url")
    remove = sub.add_parser("remove")
    remove.add_argument("name")
    for op in ("enable", "disable", "show"):
        sub.add_parser(op)
    args = parser.parse_args()

    try:
        if args.command == "generate":
            config = load_config(args.config)
            if not config["enabled"]:
                raise ValueError("Multi-server subscription is disabled")
            provider_yaml, multi_yaml = render_files(
                args.single.read_text(encoding="utf-8"), config["peers"]
            )
            atomic_text(args.provider, provider_yaml)
            atomic_text(args.multi, multi_yaml)
        elif args.command == "show":
            # Do not echo token-bearing peer URLs in normal status output.
            config = load_config(args.config)
            print("enabled:", config["enabled"])
            print("peers:", ", ".join(p["name"] for p in config["peers"]) or "(none)")
        else:
            edit_config(args.config, args.command,
                        getattr(args, "name", None), getattr(args, "url", None))
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        parser.exit(1, "multi-server: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
