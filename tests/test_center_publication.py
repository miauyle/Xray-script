"""Standalone/center Nginx subscription publication regression without root."""
import re
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "core" / "clash.sh").read_text(encoding="utf-8")


def extract_shell_function(name):
    match = re.search(
        r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}\s*$",
        SOURCE,
    )
    if match is None:
        raise AssertionError("Function missing: " + name)
    return match.group(0)


class PublicationNginxTests(unittest.TestCase):
    def generate(self, center):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "old-provider-token").write_text("legacy-secret\n")
            (root / "next-provider-token").write_text("")
            conf = root / "published.conf"
            def assign(k, v):
                return k + "=" + shlex.quote(str(v))
            lines = [
                "set -e",
                assign("NGINX_SUB_CONFIG", conf),
                assign("CLASH_CONFIG_PATH", root / "clash.yaml"),
                assign("PROVIDER_YAML_PATH", root / "proxies.yaml"),
                assign("MULTI_YAML_PATH", root / "multi_clash.yaml"),
                assign("SHADOWROCKET_NODES_PATH", root / "multi_nodes.txt"),
                assign("MULTI_TOKEN_PATH", root / "multi-token"),
                assign("PROVIDER_TOKEN_PATH", root / "old-provider-token"),
                assign("PROVIDER_NEXT_TOKEN_PATH", root / "next-provider-token"),
                assign("CENTER", "1" if center else "0"),
                "multi_is_enabled() { [[ \"$CENTER\" == 1 ]]; }",
                "multi_read_token() { [[ -s \"$1\" ]] && tr -d '[:space:]' <\"$1\" || true; }",
                "current_token() { printf '%s' single-secret; }",
                extract_shell_function("write_nginx_subscription_config"),
                "write_nginx_subscription_config single-secret",
            ]
            if center:
                (root / "multi-token").write_text("center-secret\n")
            done = subprocess.run(["bash", "-c", "\n".join(lines)],
                                  cwd=ROOT, capture_output=True, text=True, timeout=12)
            self.assertEqual(done.returncode, 0, done.stderr)
            return conf.read_text()

    def test_leaf_exports_both_standalone_files_but_no_center_routes(self):
        config = self.generate(center=False)
        self.assertIn("location = /sub/single-secret/clash.yaml", config)
        self.assertIn("location = /sub/single-secret/proxies.yaml", config)
        self.assertIn("location = /sub/legacy-secret/proxies.yaml", config)
        self.assertNotIn("multi_clash.yaml", config)
        self.assertNotIn("multi_nodes.txt", config)

    def test_center_exports_same_leaf_routes_plus_two_aggregates(self):
        config = self.generate(center=True)
        self.assertIn("location = /sub/center-secret/multi_clash.yaml", config)
        self.assertIn("location = /sub/center-secret/multi_nodes.txt", config)
        self.assertIn("location = /sub/single-secret/proxies.yaml", config)
        self.assertEqual(config.count("location = /sub/legacy-secret/proxies.yaml"), 1)
        self.assertEqual(config.count("location = /sub/single-secret/proxies.yaml"), 1)


if __name__ == "__main__":
    unittest.main()
