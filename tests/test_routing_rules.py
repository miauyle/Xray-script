"""Regression tests for compact Mihomo routing rules and center inheritance."""
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core"))
import clash_multi

RULES = [
    "GEOSITE,private,DIRECT",
    "DOMAIN-SUFFIX,local,DIRECT",
    "DOMAIN-SUFFIX,lan,DIRECT",
    "DOMAIN-SUFFIX,home.arpa,DIRECT",
    "GEOIP,private,DIRECT,no-resolve",
    "GEOSITE,category-ads-all,REJECT",
    "GEOSITE,steam@cn,DIRECT",
    "GEOSITE,microsoft@cn,DIRECT",
    "GEOSITE,CN,DIRECT",
    "GEOIP,CN,DIRECT",
    "MATCH,Proxy",
]


def emitted_routing_rules():
    """Read the actual routing heredoc of core/clash.sh, not the README."""
    source = (ROOT / "core" / "clash.sh").read_text(encoding="utf-8")
    generator = source.split("function generate_yaml() {", 1)[1].split(
        "\nfunction current_token()", 1
    )[0]
    header = "# Routing rules\n# =========================\nrules:\n"
    if generator.count(header) != 1:
        raise AssertionError("Expected one generated routing section")
    body = generator.split(header, 1)[1].split("\nEOF_YAML", 1)[0]
    entries = [line.strip()[2:].strip() for line in body.splitlines()
               if line.strip().startswith("- ")]
    return entries


class MihomoRoutingRulesTests(unittest.TestCase):
    def test_rules_are_explicit_ordered_and_use_supported_categories(self):
        actual = emitted_routing_rules()
        self.assertEqual(actual, RULES)
        self.assertNotIn("GEOIP,lan,DIRECT,no-resolve", actual)
        self.assertNotIn("GEOIP,CN,DIRECT,no-resolve", actual)

    def test_center_and_standalone_use_identical_rule_suffix(self):
        routing_body = "\n".join("  - " + rule for rule in emitted_routing_rules()) + "\n"
        single = (
            "mixed-port: 7890\n"
            + clash_multi.PROXY_MARKER
            + "  - name: 'Fallback-Vision-Reality'\n"
            + "    type: vless\n"
            + "    server: '198.51.100.1'\n"
            + "    port: 443\n"
            + clash_multi.GROUP_MARKER
            + "  - name: Proxy\n    type: select\n    proxies:\n"
            + "      - Auto\n"
            + clash_multi.RULE_MARKER
            + routing_body
        )
        peer = {"name": "Chuncheon",
                "url": "http://198.51.100.2/sub/" + "x" * 22 + "/proxies.yaml"}
        for peers in ([], [peer]):
            provider, multi = clash_multi.render_files(single, peers)
            self.assertEqual(multi.split(clash_multi.RULE_MARKER, 1)[1],
                             routing_body)
            self.assertEqual(multi.count("  - MATCH,Proxy"), 1)
            self.assertNotIn("rules:", provider)
            self.assertNotIn("GEOIP,CN,DIRECT", provider)
            # No new DNS/TUN policy should be injected by the aggregator.
            self.assertNotIn("\ndns:", multi)
            self.assertNotIn("\ntun:", multi)


if __name__ == "__main__":
    unittest.main()
