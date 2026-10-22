"""Integration coverage for persistent Xray logs and safe non-root repair.

The main test discovery runs unprivileged (and skips these tests). CI separately
runs this file under sudo to exercise actual Linux ownership and runuser.
"""
import json
import os
import shlex
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "core" / "xray_logs.sh"


@unittest.skipUnless(os.geteuid() == 0, "requires root; CI runs with sudo")
class FileLogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.root.chmod(0o755)
        self.logdir = self.root / "logs"
        self.config = self.root / "config.json"
        self.set_config()
        self.user, self.group = "nobody", "nogroup"

    def set_config(self, paths=None):
        if paths is None:
            paths = [self.logdir / "access.log", self.logdir / "error.log"]
        self.config.write_text(json.dumps({
            "log": {"access": str(paths[0]), "error": str(paths[1])}
        }), encoding="utf-8")

    def call_preflight(self):
        code = r"""
systemctl() {
    case "$*" in
      *" -p User "*) echo "$MOCK_SERVICE_USER" ;;
      *" -p Group "*) echo "$MOCK_SERVICE_GROUP" ;;
      *" -p DynamicUser "*) echo no ;;
      *) return 88 ;;
    esac
}
source "$1"
xray_prepare_log_files "$2"
"""
        return subprocess.run(
            ["bash", "-c", code, "_", str(HELPER), str(self.config)],
            text=True, capture_output=True, timeout=15,
            env={**os.environ, "XRAY_LOG_DIR": str(self.logdir),
                 "MOCK_SERVICE_USER": self.user,
                 "MOCK_SERVICE_GROUP": self.group},
        )

    def test_root_owned_logs_are_backed_up_then_new_logs_are_nonroot_writable(self):
        self.logdir.mkdir(mode=0o700)
        for name in ("access", "error"):
            file = self.logdir / f"{name}.log"
            file.write_text(f"{name}: keep these historical lines\n")
            file.chmod(0o600)
        result = self.call_preflight()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.logdir.stat().st_uid, 65534)
        for name in ("access", "error"):
            file = self.logdir / f"{name}.log"
            backups = list(self.logdir.glob(f"{name}.log.backup-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), f"{name}: keep these historical lines\n")
            self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o600)
            self.assertEqual(backups[0].stat().st_uid, 0)
            self.assertEqual(file.stat().st_uid, 65534)
            self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o640)
            writable = subprocess.run(["runuser", "-u", "nobody", "-g", "nogroup",
                                       "--", "test", "-w", str(file)])
            self.assertEqual(writable.returncode, 0)

        # A second invocation must never clear or rotate healthy logs.
        (self.logdir / "access.log").write_text("new session\n")
        again = self.call_preflight()
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual((self.logdir / "access.log").read_text(), "new session\n")
        self.assertEqual(len(list(self.logdir.glob("access.log.backup-*"))), 1)

    def test_missing_files_are_created_without_backups(self):
        result = self.call_preflight()
        self.assertEqual(result.returncode, 0, result.stderr)
        for filename in ("access.log", "error.log"):
            file = self.logdir / filename
            self.assertEqual(file.stat().st_uid, 65534)
            self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o640)
        self.assertFalse(list(self.logdir.glob("*.backup-*")))

    def test_existing_writable_root_service_logs_stay_unchanged(self):
        self.user = "root"
        self.group = "root"
        self.logdir.mkdir(mode=0o700)
        for name in ("access", "error"):
            (self.logdir / f"{name}.log").write_text("do not truncate\n")
        r = self.call_preflight()
        self.assertEqual(r.returncode, 0, r.stderr)
        for name in ("access", "error"):
            self.assertEqual((self.logdir / f"{name}.log").read_text(), "do not truncate\n")
        self.assertFalse(list(self.logdir.glob("*.backup-*")))

    def test_rejects_symlink_without_touching_target(self):
        self.logdir.mkdir()
        target = self.root / "do-not-touch"
        target.write_text("untouched\n")
        (self.logdir / "access.log").symlink_to(target)
        result = self.call_preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.logdir / "access.log").is_symlink())
        self.assertEqual(target.read_text(), "untouched\n")

    def test_rejects_hardlink(self):
        self.logdir.mkdir()
        target = self.root / "shared-hardlink"
        target.write_text("unchanged\n")
        os.link(target, self.logdir / "access.log")
        result = self.call_preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "unchanged\n")

    def test_rejects_unrelated_ownership(self):
        self.user, self.group = "root", "root"
        self.logdir.mkdir()
        os.chown(self.logdir, 65534, 65534)
        result = self.call_preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.logdir.stat().st_uid, 65534)


if __name__ == "__main__":
    unittest.main()
