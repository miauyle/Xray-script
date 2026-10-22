"""Exercise production Xray config apply/rollback against a real release binary.

Called by the Xray v26.3.27 and v26.10.21 CI matrix, not a mocked xray.
Uses a temporary directory, no systemd operations and no live configuration.
"""
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = str(pathlib.Path(sys.argv[1]).resolve())
HANDLER = (ROOT / "core" / "handler.sh").read_text(encoding="utf-8")


def function(name):
    match = re.search(r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}",
                      HANDLER)
    if not match:
        raise AssertionError("Missing production function: " + name)
    return match.group(0)


with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td)
    installed = root / "config.json"
    backup = root / "backup.json"
    old = {"log": {"loglevel": "warning"}, "outbounds": [
        {"tag": "old", "protocol": "freedom"}]}
    current = {"log": {"loglevel": "warning"}, "outbounds": [
        {"tag": "new", "protocol": "freedom"}]}
    backup.write_text(json.dumps(old))
    code = "\n".join([
        "XRAY_CONFIG_PATH=" + shlex.quote(str(installed)),
        "SCRIPT_CONFIG_PENDING_PATH=" + shlex.quote(str(root / "missing-pending")),
        "XRAY_CONFIG=" + shlex.quote(json.dumps(current)),
        "XRAY_REAL_BINARY=" + shlex.quote(BINARY),
        'xray() { "$XRAY_REAL_BINARY" "$@"; }',
        '_error() { echo "ERROR: $*" >&2; exit 90; }',
        'xray_prepare_log_files() { return 0; }',
        'backup_xray_config() { :; }',
        'restart_xray_service_checked() { return 0; }',
        'clear_pending_script_config() { :; }',
        function("apply_xray_config"),
        function("rollback_xray_config"),
        'apply_xray_config ci:full-fresh-install || exit 91',
        '[[ -f "$XRAY_CONFIG_PATH" ]] || exit 92',
        'rollback_xray_config ' + shlex.quote(str(backup)) + ' ci:rollback || exit 93',
    ])
    result = subprocess.run(["bash", "-c", code], text=True,
                            capture_output=True, cwd=ROOT, timeout=25)
    if result.returncode:
        raise RuntimeError(
            f"Real Xray apply/rollback failed ({result.returncode}):\n"
            + result.stdout + result.stderr
        )
    if json.loads(installed.read_text()) != old:
        raise AssertionError("Production rollback did not restore old JSON")
    if list(root.glob("config.json.tmp.*")) or list(root.glob("config.json.rollback.*")):
        raise AssertionError("Staging files leaked after apply/rollback")
    print("PASS actual Xray: fresh config staging, JSON parser and rollback")
