"""Validate generated Xray templates with an actual pinned Xray binary.

Usage: python3 tests/check_real_xray_templates.py /path/to/xray
This uses synthetic credentials and binds to loopback only.
"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
XRAY = str(pathlib.Path(sys.argv[1]).resolve())

keys = subprocess.run([XRAY, "x25519"], text=True, capture_output=True, check=True)
match = re.search(r"(?im)^Private(?:\s*key)?\s*:\s*(\S+)", keys.stdout)
if not match:
    raise RuntimeError("Unable to parse private key from Xray x25519 output")
private_key = match.group(1)

# SNI template expects the Nginx UDS directory created by the full installer.
# Provide it in this isolated Linux runner without modifying the template.
pathlib.Path("/dev/shm/nginx").mkdir(parents=True, exist_ok=True)

for i, template in enumerate(sorted((ROOT / "config" / "xray").glob("*.json"))):
    obj = json.loads(template.read_text(encoding="utf-8"))
    for j, inbound in enumerate(obj.get("inbounds", [])):
        if isinstance(inbound.get("port"), int):
            inbound["listen"] = "127.0.0.1"
            inbound["port"] = 21000 + i * 8 + j
        for client in inbound.get("settings", {}).get("clients", []):
            if "id" in client:
                client["id"] = str(uuid.uuid4())
            if "password" in client:
                client["password"] = "test-only-password"
        stream = inbound.get("streamSettings", {})
        reality = stream.get("realitySettings")
        if isinstance(reality, dict):
            reality["target"] = "www.cloudflare.com:443"
            reality["serverNames"] = ["www.cloudflare.com"]
            reality["privateKey"] = private_key
            reality["shortIds"] = ["01234567"]
        if "xhttpSettings" in stream:
            stream["xhttpSettings"]["path"] = "/test-xhttp"
    with tempfile.TemporaryDirectory() as td:
        cfg = pathlib.Path(td) / "config.json"
        cfg.write_text(json.dumps(obj), encoding="utf-8")
        if template.name == "mKCP.json":
            # Run the same production compatibility probe used by handler.sh.
            selected = pathlib.Path(td) / "selected.json"
            subprocess.run(
                ["bash", "-c",
                 'source "$1"; XRAY_BINARY_PATH="$2"; '
                 'xray_mkcp_select_mask "$(cat "$3")" >"$4"',
                 "_", str(ROOT / "core" / "xray_mkcp_compat.sh"),
                 XRAY, str(cfg), str(selected)],
                check=True, timeout=15,
            )
            cfg.write_bytes(selected.read_bytes())
        command = [XRAY, "run", "-test", "-format=json", "-c", str(cfg)]
        check = subprocess.run(command, text=True, capture_output=True, timeout=15)
        if check.returncode != 0:
            raise RuntimeError(
                f"{template.name} failed real Xray config validation:\n"
                + check.stdout + check.stderr
            )
        proc = subprocess.Popen(
            [XRAY, "run", "-format=json", "-c", str(cfg)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        try:
            proc.wait(timeout=2)
            output = proc.stdout.read() if proc.stdout else ""
            raise RuntimeError(f"{template.name} exited prematurely: {output}")
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate(timeout=5)
        print(f"PASS {template.name}: config and 2-second process health")
