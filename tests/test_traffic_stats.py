"""Test the production Xray stats viewer with deterministic CLI/API fixtures."""
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tool" / "traffic.sh"


class TrafficStatsTests(unittest.TestCase):
    def run_viewer(self, response, *args, fail=False):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            fixture = work / "api.json"
            fixture.write_text(response if isinstance(response, str) else json.dumps(response))
            fake = work / "xray"
            fake.write_text("""#!/usr/bin/env bash
printf '%s\\n' "$@" >"$XRAY_TEST_ARGUMENTS"
if [[ "$XRAY_TEST_FAIL" == 1 ]]; then
    echo "connection refused" >&2
    exit 7
fi
cat "$XRAY_TEST_FIXTURE"
""")
            fake.chmod(0o755)
            arguments = work / "arguments"
            env = os.environ.copy()
            env.update({
                "XRAY_BIN": str(fake),
                "XRAY_STATS_SERVER": "127.0.0.1:32768",
                "XRAY_TEST_FIXTURE": str(fixture),
                "XRAY_TEST_ARGUMENTS": str(arguments),
                "XRAY_TEST_FAIL": "1" if fail else "0",
            })
            process = subprocess.run(["bash", str(SCRIPT), *args],
                                     env=env, capture_output=True, text=True, timeout=20)
            return process, arguments.read_text() if arguments.exists() else ""

    @staticmethod
    def entries(*items):
        return {"stat": [{"name": name, "value": str(value)}
                         for name, value in items]}

    def test_default_is_read_only_and_totals_are_independent(self):
        data = self.entries(
            ("inbound>>>api>>>traffic>>>uplink", 170),
            ("inbound>>>VLESS-Vision-REALITY>>>traffic>>>uplink", 302000),
            ("inbound>>>VLESS-XHTTP-REALITY>>>traffic>>>uplink", 51000),
            ("inbound>>>VLESS-XHTTP-REALITY>>>traffic>>>downlink", 24000),
            ("outbound>>>direct>>>traffic>>>uplink", 285000),
            ("outbound>>>direct>>>traffic>>>downlink", 46000),
            ("outbound>>>warp>>>traffic>>>uplink", 0),
            ("user>>>vless@xtls.reality>>>traffic>>>uplink", 235000),
            ("user>>>vless@xhttp.reality>>>traffic>>>uplink", 51000),
            ("user>>>vless@xtls.reality>>>traffic>>>downlink", 22000),
            ("user>>>vless@xhttp.reality>>>traffic>>>downlink", 24000),
        )
        p, args = self.run_viewer(data, "--raw")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("--reset=false", args)
        self.assertNotIn("--reset=true", args)
        self.assertIn("inbound:VLESS-Vision-REALITY->up", p.stdout)
        self.assertIn("outbound:warp->up", p.stdout)
        self.assertIn("0B", p.stdout)
        sections = re.split(r"------------(?:Inbound|Outbound|User)----------", p.stdout)
        self.assertIn("353170B", sections[1])
        self.assertIn("331000B", sections[2])
        self.assertIn("332000B", sections[3])
        self.assertIn("do NOT add their totals", p.stdout)

    def test_missing_zero_values_and_unrelated_online_metrics(self):
        data = {"stat": [
            {"name": "outbound>>>warp>>>traffic>>>uplink"},
            {"name": "user>>>vless@xtls.reality>>>online", "value": "42"},
            {"name": "user>>>vless@xtls.reality>>>traffic>>>downlink", "value": "0"},
        ]}
        p, args = self.run_viewer(data, "--raw")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("outbound:warp->up", p.stdout)
        self.assertIn("0B", p.stdout)
        self.assertNotIn("online", p.stdout)

    def test_very_large_integer_stays_exact_not_float(self):
        n = 9007199254740993  # 2^53 + 1, which awk float64 would round
        data = self.entries(("outbound>>>direct>>>traffic>>>uplink", n))
        p, _ = self.run_viewer(data, "--raw")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn(f"{n}B", p.stdout)
        self.assertNotIn("9007199254740992B", p.stdout)

    def test_labels_containing_link_are_preserved(self):
        data = self.entries(("user>>>tunnel-link@example.com>>>traffic>>>downlink", 1050))
        p, _ = self.run_viewer(data, "--raw")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("user:tunnel-link@example.com->down", p.stdout)

    def test_invalid_json_and_invalid_values_fail_no_false_zero(self):
        for bad in ('not JSON!', '{"stat":"unexpected"}',
                    '{"stat":[{"name":"outbound>>>warp>>>traffic>>>uplink","value":"-1"}]}'):
            with self.subTest(bad=bad):
                p, _ = self.run_viewer(bad)
                self.assertNotEqual(p.returncode, 0)
                self.assertIn("ERROR", p.stderr)
                self.assertNotIn("SUM->TOTAL:", p.stdout)

    def test_query_error_does_not_show_zero_table(self):
        p, _ = self.run_viewer({"stat": []}, fail=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("connection refused", p.stderr)
        self.assertIn("ERROR", p.stderr)
        self.assertNotIn("SUM->TOTAL:", p.stdout)

    def test_reset_is_only_explicit_and_marked(self):
        data = self.entries(("outbound>>>direct>>>traffic>>>downlink", 3))
        p, args = self.run_viewer(data, "reset")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("--reset=true", args)
        self.assertIn("pre-reset values", p.stdout)

    def test_empty_valid_stats_response(self):
        p, _ = self.run_viewer({})
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout.count("(no counters for this category)"), 3)


if __name__ == "__main__":
    unittest.main()
