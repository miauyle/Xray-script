"""Offline ACME/HTTPS safety tests; no ACME account, systemd or firewall changes."""
import json
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core"))
import clash_https as https


class HttpsManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def test_domain_validation_rejects_injections(self):
        for bad in ("", "foo", "evil;command.com", "x..com", "-x.com", "x.com/", "a b.com"):
            with self.subTest(domain=bad), self.assertRaises(ValueError):
                https.validate_domain(bad)
        self.assertEqual(https.validate_domain("myhost.dynu.net"), "myhost.dynu.net")

    def test_dns_cert_install_and_renewal_hook_are_scoped(self):
        calls = []
        def mock_run(args, **kwargs):
            calls.append((args, kwargs.get("env", {})))
            if args[0] == "openssl":
                return "Hostname myhost.dynu.net does match certificate"
            if "--install-cert" in args:
                (self.base / "tls/privkey.pem").write_text("key")
                (self.base / "tls/fullchain.pem").write_text("cert")
            return ""
        with patch.object(https, "acme_bin", return_value="/mock/acme.sh"), \
             patch.object(https, "run", side_effect=mock_run), \
             patch.object(https, "configure_timer") as timer:
            https.issue(self.base, "dns", "myhost.dynu.net", "id", "secret")
        self.assertIn("--dns", calls[0][0])
        self.assertIn("dns_dynu", calls[0][0])
        self.assertEqual(calls[0][1]["Dynu_Secret"], "secret")
        self.assertIn("--install-cert", calls[1][0])
        self.assertIn("systemctl try-restart xray-center-https.service", calls[1][0])
        self.assertEqual(json.loads((self.base / "https-certificate.json").read_text())["method"], "dns")
        self.assertEqual((self.base / "tls/privkey.pem").stat().st_mode & 0o777, 0o600)
        timer.assert_called_once()

    def test_issue_failure_keeps_previous_method(self):
        https.save_secure(self.base / "https-certificate.json",
                          {"domain": "myhost.dynu.net", "method": "dns"})
        with patch.object(https, "acme_bin", return_value="/mock/acme.sh"), \
             patch.object(https, "run", side_effect=RuntimeError("failed")):
            with self.assertRaises(RuntimeError):
                https.issue(self.base, "http", "myhost.dynu.net")
        self.assertEqual(json.loads((self.base / "https-certificate.json").read_text())["method"], "dns")

    def test_443_conflict_refused_before_systemd_change(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.bind(("0.0.0.0", 0))
            port = listener.getsockname()[1]
            listener.listen()
            with self.assertRaises(ValueError):
                https.test_port(port)
        self.assertFalse((self.base / "https-center.json").exists())

    def test_https_requires_certificate_and_static_files(self):
        with self.assertRaises(ValueError):
            https.enable_https(self.base, Path("/missing/server.py"), self.base / "token",
                               self.base / "multi.yaml", self.base / "nodes.txt",
                               self.base / "clash.yaml", 8443)

if __name__ == "__main__":
    unittest.main()
