"""Tests for strict SFTP pull and static multi-client subscriptions."""
import base64
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core"))
import clash_multi as multi
import clash_shadowrocket as shadow
import clash_ssh as ssh

def provider(host, name="Vision"):
    return ("proxies:\n  - name: '" + name + "'\n"
            "    type: vless\n    server: '" + host + "'\n"
            "    port: 443\n    uuid: '2c776d0d-c427-4769-bfaa-660628e74722'\n"
            "    network: tcp\n    tls: true\n    flow: xtls-rprx-vision\n"
            "    servername: 'www.example.com'\n    client-fingerprint: chrome\n"
            "    reality-opts:\n      public-key: 'example-key'\n"
            "      short-id: 'ab12'\n      support-x25519mlkem768: true\n")

SINGLE = ("mixed-port: 7890\nmode: rule\n" + multi.PROXY_MARKER
          + provider("198.51.100.1").split("proxies:\n", 1)[1]
          + multi.GROUP_MARKER + "  - name: Proxy\n    type: select\n    proxies:\n      - Vision\n"
          + multi.RULE_MARKER + "  - DOMAIN-SUFFIX,apple.com,DIRECT\n"
          + "  - GEOIP,CN,DIRECT,no-resolve\n  - MATCH,Proxy\n")


class SshTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.key = self.root / "sync_key"
        self.key.write_text("private")
        self.key.chmod(0o600)
        self.known = self.root / "known_hosts"
        self.known.write_text("example.invalid ssh-ed25519 AAAA\n")
        self.cfg = self.root / "ssh-peers.json"
        self.local = self.root / "proxies.yaml"
        self.local.write_text(provider("198.51.100.1"))
        self.single = self.root / "clash.yaml"
        self.single.write_text(SINGLE)
        self.cache = self.root / "cache"
        self.yaml = self.root / "multi_clash.yaml"
        self.txt = self.root / "multi_nodes.txt"

    def peer(self, name="Tokyo", port=2222):
        return dict(name=name, host="example.invalid", user="sync", port=port,
                    remote_path="/home/sync/.xray-script/clash/proxies.yaml",
                    key_file=str(self.key), known_hosts=str(self.known))

    def test_sftp_strict_port_and_hostkey(self):
        p = ssh.validate_peer(self.peer())
        seen = {}
        def fake(cmd, **kw):
            seen["cmd"], seen["input"] = cmd, kw["input"]
            Path(kw["input"].split()[-1]).write_text(provider("203.0.113.5"))
            return subprocess.CompletedProcess(cmd, 0)
        self.assertEqual(len(shadow.parse_provider(ssh.sftp_fetch(p, self.cache, runner=fake))), 1)
        self.assertEqual(seen["cmd"][seen["cmd"].index("-P") + 1], "2222")
        self.assertIn("-oStrictHostKeyChecking=yes", seen["cmd"])
        self.assertIn("-oUserKnownHostsFile=" + str(self.known), seen["cmd"])
        self.assertIn("proxies.yaml", seen["input"])

    def test_reject_invalid_fields_and_exposed_key(self):
        for changes in ({"port": 0}, {"port": 65536}, {"host": "x;cmd"},
                        {"remote_path": "/home/a/../b/proxies.yaml"},
                        {"remote_path": "/home/a/my file/proxies.yaml"},
                        {"user": "root;cmd"}, {"name": "bad name"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                ssh.validate_peer({**self.peer(), **changes})
        self.key.chmod(0o644)
        with self.assertRaises(ValueError):
            ssh.validate_peer(self.peer())

    def test_static_mihomo_shadowrocket_and_rule_preservation(self):
        text, encoded = ssh.merge(SINGLE, provider("198.51.100.1"),
                                  [("Tokyo", shadow.parse_provider(provider("203.0.113.5", "Remote")))])
        self.assertIn('name: "Tokyo-Remote"', text)
        self.assertNotIn("proxy-providers:", text)
        self.assertIn("support-x25519mlkem768: true", text)
        self.assertIn("consistent-hashing", text)
        self.assertIn("DOMAIN-SUFFIX,apple.com,DIRECT", text)
        self.assertIn("GEOIP,CN,DIRECT", text)
        raw = base64.b64decode(encoded).decode()
        self.assertIn("pbk=example-key", raw)
        self.assertIn("sid=ab12", raw)
        self.assertEqual(len(raw.splitlines()), 2)

    def test_invalid_sync_keeps_both_output_and_last_good_cache(self):
        ssh.edit(self.cfg, "enable")
        ssh.edit(self.cfg, "add", self.peer())
        self.cache.mkdir(mode=0o700)
        cached = ssh.cache_file(self.cache, "Tokyo")
        multi.atomic_text(cached, provider("203.0.113.4"))
        args = (ssh.load(self.cfg), self.single, self.local, self.cache, self.yaml, self.txt)
        ssh.publish(*args)
        before = (cached.read_bytes(), self.yaml.read_bytes(), self.txt.read_bytes())
        with self.assertRaises(ValueError):
            ssh.publish(*args, {"Tokyo": "not YAML"})
        self.assertEqual(before, (cached.read_bytes(), self.yaml.read_bytes(), self.txt.read_bytes()))
        ssh.publish(*args, {"Tokyo": provider("203.0.113.8")})
        self.assertIn(b"203.0.113.8", self.yaml.read_bytes())
        self.assertEqual(self.txt.stat().st_mode & 0o777, 0o600)

    def test_add_remove_config_and_token_generation(self):
        ssh.edit(self.cfg, "enable")
        ssh.edit(self.cfg, "add", self.peer())
        ssh.edit(self.cfg, "add", self.peer("Seoul", 2200))
        ssh.edit(self.cfg, "remove", name="Tokyo")
        self.assertEqual([p["name"] for p in ssh.load(self.cfg)["nodes"]], ["Seoul"])
        self.assertNotIn("http://", self.cfg.read_text())
        root = Path(__file__).resolve().parents[1]
        self.assertIn("openssl rand -base64 32", (root / "core/clash.sh").read_text())
        self.assertIn('token="$(generate_token_value)"', (root / "core/clash_multi.sh").read_text())
        for _ in range(3):
            raw = subprocess.check_output(["openssl", "rand", "-base64", "32"], text=True)
            self.assertEqual(len(raw.translate(str.maketrans("+/", "-_")).replace("=", "").strip()), 43)

if __name__ == "__main__":
    unittest.main()
