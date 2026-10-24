#!/usr/bin/env python3
"""Opt-in local-only export of proxies.yaml for a dedicated read-only SFTP account.

The target is a root-owned directory not writable by the sync user. The user
gets only group read access to the sanitized Provider (never Xray private keys).
"""
import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import re
import tempfile

from clash_multi import atomic_json
from clash_shadowrocket import MAX_PROVIDER_BYTES, parse_provider, validate_node

USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
DEFAULT_ROOT = Path("/var/lib/xray-script-sftp")


def account(name):
    if not USER_RE.fullmatch(name) or name == "root":
        raise ValueError("Use a dedicated, non-root sync account")
    try:
        person = pwd.getpwnam(name)
        group = grp.getgrgid(person.pw_gid)
    except KeyError as exc:
        raise ValueError("Sync account/private group not found") from exc
    if group.gr_name != name:
        raise ValueError("Sync user must have a dedicated private primary group")
    return person.pw_gid


def safe_dir(path, mode, group=None):
    if path.is_symlink():
        raise ValueError("Refuse symlinked export directory")
    path.mkdir(mode=mode, parents=False, exist_ok=True)
    if path.is_symlink() or not path.is_dir() or path.stat().st_uid != 0:
        raise ValueError("Export directory must be owned by root")
    if group is not None:
        os.chown(path, 0, group)
    path.chmod(mode)


def export(source, name, root=DEFAULT_ROOT):
    if os.geteuid() != 0:
        raise ValueError("Root required to create protected SFTP export")
    gid = account(name)
    if root.is_symlink():
        raise ValueError("Refuse symlinked export root")
    if not root.exists():
        root.mkdir(mode=0o755, parents=False)
    safe_dir(root, 0o755)
    directory = root / name
    safe_dir(directory, 0o750, gid)
    target = directory / "proxies.yaml"
    if target.is_symlink():
        raise ValueError("Refuse symlinked export file")
    raw = source.read_bytes()
    if len(raw) > MAX_PROVIDER_BYTES:
        raise ValueError("Provider too large")
    nodes = parse_provider(raw.decode("utf-8"))
    for node in nodes:
        validate_node(node)
    fd, temporary = tempfile.mkstemp(prefix=".proxies-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(raw)
            out.flush()
            os.fsync(out.fileno())
        os.chown(temporary, 0, gid)
        os.chmod(temporary, 0o640)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    cmd = parser.add_subparsers(dest="command", required=True)
    cmd.add_parser("publish")
    cmd.add_parser("show")
    setup = cmd.add_parser("configure")
    setup.add_argument("user")
    args = parser.parse_args()
    try:
        if args.command == "show":
            if not args.config.exists():
                print("Read-only SFTP export not enabled.")
                return
            cfg = json.loads(args.config.read_text())
            print("SFTP export configured for:", cfg["user"])
            print("Path:", DEFAULT_ROOT / cfg["user"] / "proxies.yaml")
            return
        if args.command == "configure":
            target = export(args.source, args.user)
            atomic_json(args.config, {"user": args.user})
            print("Protected SFTP-only file:", target)
        elif args.command == "publish" and args.config.exists():
            cfg = json.loads(args.config.read_text())
            print("Updated protected SFTP-only file:", export(args.source, cfg["user"]))
    except (ValueError, OSError, UnicodeError, KeyError, json.JSONDecodeError) as exc:
        parser.exit(1, "sftp-export: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
