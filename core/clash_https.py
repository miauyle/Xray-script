#!/usr/bin/env python3
"""Optional secure HTTPS publisher and Dynu ACME certificate manager for an SSH center.

Reuses the installed acme.sh binary but isolates its cert-home from Nginx certificates.
No Xray listener, SSH configuration or firewall rule is changed.
"""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile

from clash_multi import atomic_json

HOSTNAME = re.compile(r"^[a-zA-Z0-9](?:[a-zA-Z0-9.-]{1,251}[a-zA-Z0-9])$")
UNIT = Path("/etc/systemd/system/xray-center-https.service")
TIMER = Path("/etc/systemd/system/xray-center-cert-renew.timer")
RENEW_UNIT = Path("/etc/systemd/system/xray-center-cert-renew.service")


def run(cmd, *, env=None, capture=False):
    result = subprocess.run(cmd, env=env, text=True, capture_output=capture, check=False)
    if result.returncode:
        raise RuntimeError("Command failed: " + Path(str(cmd[0])).name +
                           " (exit status " + str(result.returncode) + ")")
    return result.stdout.strip() if capture else ""


def acme_bin():
    installed = Path.home() / ".acme.sh/acme.sh"
    value = str(installed) if installed.is_file() else shutil.which("acme.sh")
    if not value:
        raise ValueError("Install the existing acme.sh via service/ssl.sh first; no second ACME client is installed")
    return value


def validate_domain(domain):
    if not HOSTNAME.fullmatch(domain) or ".." in domain or "." not in domain:
        raise ValueError("Invalid DNS hostname")
    return domain


def state_paths(base):
    return {
        "cert_state": base / "https-certificate.json",
        "https_state": base / "https-center.json",
        "cert_home": base / "acme-certs",
        "cert_dir": base / "tls",
    }


def save_secure(path, value):
    atomic_json(path, value)


def issue(base, method, domain, client_id=None, secret=None, force=False):
    """Issue first, commit selected method only when deployment succeeded."""
    domain = validate_domain(domain)
    if method not in ("dns", "http"):
        raise ValueError("Select dns or http")
    p = state_paths(base)
    for path in (p["cert_dir"], p["cert_home"]):
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        path.chmod(0o700)
    acme = acme_bin()
    old = json.loads(p["cert_state"].read_text()) if p["cert_state"].exists() else {}
    command = [acme, "--issue", "--server", "letsencrypt", "--cert-home", str(p["cert_home"]), "-d", domain]
    if force or old.get("method") not in (None, method):
        command.append("--force")
    env = os.environ.copy()
    if method == "dns":
        command += ["--dns", "dns_dynu"]
        if bool(client_id) != bool(secret):
            raise ValueError("Dynu Client ID and secret must both be supplied, or both omitted to reuse saved credentials")
        if client_id:
            env["Dynu_ClientId"] = client_id
            env["Dynu_Secret"] = secret
    else:
        # ACME standalone must listen on 80. Never stop an occupied service automatically.
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check:
            try:
                check.bind(("0.0.0.0", 80))
            except OSError as exc:
                raise ValueError("Port 80 is occupied; choose DNS-01 or free port 80 explicitly") from exc
        command += ["--standalone", "--httpport", "80"]
    run(command, env=env)
    # acme.sh's persisted deploy hook runs after subsequent successful --cron renewals.
    run([acme, "--install-cert", "--cert-home", str(p["cert_home"]), "-d", domain,
         "--key-file", str(p["cert_dir"] / "privkey.pem"),
         "--fullchain-file", str(p["cert_dir"] / "fullchain.pem"),
         "--reloadcmd", "systemctl try-restart xray-center-https.service"])
    (p["cert_dir"] / "privkey.pem").chmod(0o600)
    check = run(["openssl", "x509", "-in", str(p["cert_dir"] / "fullchain.pem"),
                 "-noout", "-checkhost", domain], capture=True)
    if "does match" not in check:
        raise ValueError("Certificate does not match selected domain")
    save_secure(p["cert_state"], {"domain": domain, "method": method})
    configure_timer(acme, p["cert_home"])
    print("Certificate installed. Configure HTTPS service separately.")
    if method == "http":
        print("Keep public TCP/80 reachable via Oracle Cloud and Ubuntu for each future renewal.")


def configure_timer(acme, cert_home):
    # Persist renewals independently: default acme.sh cron does not scan custom cert-home.
    RENEW_UNIT.write_text("[Unit]\nDescription=Renew Xray center certificates\n"
                          "[Service]\nType=oneshot\n"
                          "ExecStart=" + acme + " --cron --cert-home " + str(cert_home) + "\n"
                          "UMask=0077\nNoNewPrivileges=true\n", encoding="utf-8")
    TIMER.write_text("[Unit]\nDescription=Daily Xray center certificate renewal\n"
                     "[Timer]\nOnCalendar=daily\nRandomizedDelaySec=1h\nPersistent=true\n"
                     "Unit=xray-center-cert-renew.service\n"
                     "[Install]\nWantedBy=timers.target\n", encoding="utf-8")
    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", "--now", TIMER.name])


def renew(base):
    p = state_paths(base)
    if not p["cert_state"].exists():
        raise ValueError("Certificate not configured")
    data = json.loads(p["cert_state"].read_text())
    if data["method"] == "http":
        print("HTTP-01 renewals require public TCP/80 reachable via Oracle Cloud and Ubuntu.")
    run([acme_bin(), "--renew", "--cert-home", str(p["cert_home"]),
         "-d", data["domain"], "--force"])


def test_port(port, existing_port=None):
    if port == existing_port and subprocess.run(
            ["systemctl", "-q", "is-active", UNIT.stem]).returncode == 0:
        return
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("0.0.0.0", port))
        except OSError as exc:
            raise ValueError("HTTPS port occupied (possibly Xray 443); no service changed") from exc


def enable_https(base, script, token, multi, shadowrocket, single, port):
    p = state_paths(base)
    if not p["cert_state"].exists() or not (p["cert_dir"] / "privkey.pem").exists():
        raise ValueError("Issue and deploy a valid certificate first")
    if not multi.is_file() or not shadowrocket.is_file() or not token.is_file():
        raise ValueError("Generate center static subscriptions and Token first")
    if not 1 <= port <= 65535:
        raise ValueError("Invalid HTTPS port")
    cert = json.loads(p["cert_state"].read_text())
    validate_domain(cert["domain"])
    previous = json.loads(p["https_state"].read_text()) if p["https_state"].exists() else {}
    test_port(port, previous.get("port"))
    old_unit = UNIT.read_text() if UNIT.exists() else None
    base.chmod(0o700)
    unit = (
        "[Unit]\nDescription=Independent Xray center HTTPS subscriptions\n"
        "After=network-online.target\nWants=network-online.target\n[Service]\n"
        "Type=simple\nExecStart=" + sys.executable + " " + str(script) +
        " --bind 0.0.0.0 --port " + str(port) + " --multi-token-file " + str(token) +
        " --multi-yaml-file " + str(multi) + " --shadowrocket-static-file " + str(shadowrocket) +
        " --tls-cert " + str(p["cert_dir"] / "fullchain.pem") +
        " --tls-key " + str(p["cert_dir"] / "privkey.pem") +
        ("\n" if not single else " --token-file " + str(base / "subscription.token") +
         " --yaml-file " + str(single) + "\n") +
        "Restart=on-failure\nRestartSec=2\nUMask=0077\nNoNewPrivileges=true\n"
        "PrivateTmp=true\nProtectSystem=strict\n[Install]\nWantedBy=multi-user.target\n"
    )
    UNIT.write_text(unit, encoding="utf-8")
    try:
        run(["systemctl", "daemon-reload"])
        run(["systemctl", "enable", UNIT.name])
        run(["systemctl", "restart", UNIT.name])
        run(["systemctl", "-q", "is-active", UNIT.name])
        # Verify both the cert hostname and exact token path; no -k TLS bypass.
        secret = token.read_text().strip()
        if not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", secret):
            raise ValueError("Invalid center token")
        run(["curl", "--noproxy", "*", "--fail", "--silent", "--show-error",
             "--max-time", "8", "--resolve", f"{cert['domain']}:{port}:127.0.0.1",
             f"https://{cert['domain']}:{port}/sub/{secret}/multi_clash.yaml", "-o", "/dev/null"])
    except (ValueError, RuntimeError, OSError):
        if old_unit is not None:
            UNIT.write_text(old_unit, encoding="utf-8")
            subprocess.run(["systemctl", "daemon-reload"], check=False)
            subprocess.run(["systemctl", "restart", UNIT.name], check=False)
        else:
            subprocess.run(["systemctl", "disable", "--now", UNIT.name], check=False)
            UNIT.unlink(missing_ok=True)
            subprocess.run(["systemctl", "daemon-reload"], check=False)
        raise
    save_secure(p["https_state"], {"domain": cert["domain"], "port": port})
    print("Local HTTPS hostname and token route test PASS.")
    print("Verify public reachability via Oracle security rules/NSG and host firewall before retiring old HTTP.")


def status(base):
    p = state_paths(base)
    for name in ("cert_state", "https_state"):
        print(name + ":", p[name].read_text().strip() if p[name].exists() else "(not configured)")
    cert = p["cert_dir"] / "fullchain.pem"
    if cert.exists():
        run(["openssl", "x509", "-in", str(cert), "-noout", "-dates"])
    for unit in (UNIT.name, TIMER.name):
        result = subprocess.run(["systemctl", "is-active" if unit == UNIT.name else "is-enabled",
                                 unit], capture_output=True, text=True)
        print(unit + ":", result.stdout.strip() or "inactive")


def audit():
    for cmd in (["ss", "-ltnp"], ["sshd", "-T"], ["ufw", "status"]):
        if not shutil.which(cmd[0]):
            continue
        try:
            raw = run(cmd, capture=True)
            if cmd[0] == "sshd":
                raw = "\n".join(line for line in raw.splitlines() if line.startswith((
                    "port ", "passwordauthentication ", "pubkeyauthentication ", "permitrootlogin ")))
            if cmd[0] == "ss":
                raw = "\n".join(line for line in raw.splitlines() if "sshd" in line or ":22 " in line)
            print(cmd[0] + ":\n" + raw)
        except RuntimeError:
            print(cmd[0] + ": unavailable")
    print("Oracle Cloud Security Lists / NSG require cloud-console verification; no SSH port is changed.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--server-script", type=Path)
    parser.add_argument("--token", type=Path)
    parser.add_argument("--multi", type=Path)
    parser.add_argument("--shadowrocket", type=Path)
    parser.add_argument("--single", type=Path)
    parser.add_argument("--port", type=int, default=8443)
    sub = parser.add_subparsers(dest="action", required=True)
    issue_cmd = sub.add_parser("issue")
    issue_cmd.add_argument("--method", choices=["dns", "http"], required=True)
    issue_cmd.add_argument("--domain", required=True)
    issue_cmd.add_argument("--force", action="store_true")
    for action in ("renew", "start", "status", "audit"):
        sub.add_parser(action)
    args = parser.parse_args()
    try:
        args.base.mkdir(mode=0o700, parents=True, exist_ok=True)
        if args.action == "issue":
            if args.method == "http":
                print("HTTP-01 needs inbound public TCP/80 in BOTH Oracle and Ubuntu, including renewals.")
                if input("I verified both ingress policies (type yes): ") != "yes":
                    return 1
            client = secret = None
            if args.method == "dns":
                print("Dynu OAuth2 API credentials; empty means previously saved acme.sh values.")
                client = input("Dynu Client ID: ") or None
                secret = getpass.getpass("Dynu Secret: ") or None
            issue(args.base, args.method, args.domain, client, secret, args.force)
        elif args.action == "renew":
            renew(args.base)
        elif args.action == "start":
            enable_https(args.base, args.server_script, args.token, args.multi,
                         args.shadowrocket, args.single, args.port)
        elif args.action == "status":
            status(args.base)
        else:
            audit()
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print("https-center: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
