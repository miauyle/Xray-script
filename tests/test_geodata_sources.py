"""GeoSite/GeoIP sources in generated Mihomo configs remain official and intact."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLASH_SH = (ROOT / "core" / "clash.sh").read_text(encoding="utf-8")

import sys
sys.path.insert(0, str(ROOT / "core"))
import clash_multi

OFFICIAL = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/"


class GeodataSourceTests(unittest.TestCase):
    def test_single_subscription_uses_official_release_binary_urls(self):
        # Restrict assertions to the YAML generator block, not README notes.
        start = CLASH_SH.index("function generate_yaml()")
        end = CLASH_SH.index("function current_token()", start)
        block = CLASH_SH[start:end]
        self.assertIn("geodata-mode: true", block)
        self.assertIn("geo-auto-update: true", block)
        self.assertIn('geoip: "' + OFFICIAL + 'geoip.dat"', block)
        self.assertIn('geosite: "' + OFFICIAL + 'geosite.dat"', block)
        self.assertNotIn("testingcf.jsdelivr.net", block)

    def test_multi_subscription_preserves_same_geodata_sources(self):
        # The aggregate must not replace the top-level geox-url block or
        # accidentally replace upstream .dat databases with ruleset files.
        original = (clash_multi.PROXY_MARKER +
                    "  - name: 'Vision-Reality'\\n" +
                    "    type: vless\\n" +
                    "    server: 198.51.100.10\\n" +
                    "    port: 443\\n")
        header = (
            "geodata-mode: true\\n"
            "geox-url:\\n"
            '  geoip: "' + OFFICIAL + 'geoip.dat"\\n' +
            '  geosite: "' + OFFICIAL + 'geosite.dat"\\n'
        )
        single = (
            header + original + clash_multi.GROUP_MARKER +
            "  - name: Proxy\\n    type: select\\n" +
            clash_multi.RULE_MARKER +
            "  - GEOSITE,CN,DIRECT\\n"
        )
        provider, multi = clash_multi.render_files(single, [])
        self.assertEqual(multi.count(OFFICIAL + "geoip.dat"), 1)
        self.assertEqual(multi.count(OFFICIAL + "geosite.dat"), 1)
        self.assertEqual(provider.count(OFFICIAL), 0)


if __name__ == "__main__":
    unittest.main()
