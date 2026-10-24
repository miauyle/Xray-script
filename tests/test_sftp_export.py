"""Protected leaf SFTP export has no HTTP listener, private keys or public files."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core"))
import clash_export
import clash_shadowrocket
from test_ssh_aggregate import provider

class ExportTests(unittest.TestCase):
    def test_export_atomic_and_only_account_group_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sftp-root"
            src = Path(tmp) / "proxies.yaml"
            src.write_text(provider("198.51.100.22"))
            # Permission-changing OS operations require root in production.
            # Here mock the OS identity and directory ownership while exercising
            # real atomic file I/O in a temporary directory.
            def safe_dir(p, mode, group=None):
                p.mkdir(mode=mode, exist_ok=True)
                p.chmod(mode)
            with patch.object(clash_export.os, "geteuid", return_value=0), \
                 patch.object(clash_export, "account", return_value=2345), \
                 patch.object(clash_export, "safe_dir", side_effect=safe_dir), \
                 patch.object(clash_export.os, "chown"):
                output = clash_export.export(src, "xraysync", root)
                self.assertEqual(output.stat().st_mode & 0o777, 0o640)
                self.assertEqual(output.read_text(), src.read_text())
                src.write_text(provider("203.0.113.34"))
                clash_export.export(src, "xraysync", root)
                self.assertIn("203.0.113.34", output.read_text())
                src.write_text("invalid\n")
                with self.assertRaises(ValueError):
                    clash_export.export(src, "xraysync", root)
                self.assertIn("203.0.113.34", output.read_text())

    def test_private_user_group_required(self):
        with patch.object(clash_export.pwd, "getpwnam",
                          return_value=SimpleNamespace(pw_gid=2345)), \
             patch.object(clash_export.grp, "getgrgid",
                          return_value=SimpleNamespace(gr_name="shared")):
            with self.assertRaises(ValueError):
                clash_export.account("xraysync")
        with self.assertRaises(ValueError):
            clash_export.account("root")

if __name__ == "__main__":
    unittest.main()
