#!/usr/bin/env python3
"""Exercise packaging failure paths with disposable bundles and mocked signing."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("package-app.sh").resolve()


class PackageSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="blinker-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tools = self.root / "bin"
        self.tools.mkdir()
        self.binary = self.root / "Blinker"
        self.binary.write_text("#!/bin/sh\nexit 0\n")
        self.binary.chmod(0o755)
        self.output = self.root / "Blinker.app"
        self.bundle_id = "com.ygnstudio.Blinker.test"
        self.mock("xcrun", "exit 1")
        self.mock("codesign", 'exit "${SIGN_EXIT:-0}"')
        self.env = dict(os.environ, PATH=f"{self.tools}:/usr/bin:/bin:/usr/sbin:/sbin",
                        CODESIGN_IDENTITY="-", BLINKER_BUNDLE_ID=self.bundle_id)

    def mock(self, name, body):
        path = self.tools / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def existing_app(self, identifier=None):
        contents = self.output / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier or self.bundle_id,
        }))
        (contents / "old-copy").write_text("preserve me")

    def package(self):
        return subprocess.run(["/bin/zsh", str(SCRIPT), str(self.binary), "1.0", "1", str(self.output)],
                              env=self.env, capture_output=True, text=True)

    def test_sign_failure_keeps_installed_app(self):
        self.existing_app()
        self.env["SIGN_EXIT"] = "1"
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.output / "Contents/old-copy").exists())
        self.assertNotIn("packaged:", result.stdout)

    def test_verification_failure_keeps_installed_app(self):
        self.existing_app()
        self.mock("codesign", 'case "$1" in --verify) exit 1;; esac\nexit 0')
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.output / "Contents/old-copy").exists())
        self.assertNotIn("packaged:", result.stdout)

    def test_interruption_preserves_previous_app(self):
        self.existing_app()
        self.mock("mv", '/bin/mv "$@" || exit 1\n'
                        'case "$2" in */previous.app) kill -TERM "$PPID";; esac')
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        backups = list(self.root.glob(".Blinker-package.*/previous.app/Contents/old-copy"))
        self.assertEqual(len(backups), 1)
        self.assertNotIn("packaged:", result.stdout)

    def test_foreign_bundle_and_symlink_are_rejected(self):
        self.existing_app("com.example.Other")
        self.assertNotEqual(self.package().returncode, 0)
        self.assertTrue((self.output / "Contents/old-copy").exists())
        original = self.output
        self.output = self.root / "Alias.app"
        self.output.symlink_to(original)
        self.assertNotEqual(self.package().returncode, 0)
        self.assertTrue((original / "Contents/old-copy").exists())

    def test_concurrent_install_lock_is_respected(self):
        self.existing_app()
        Path(str(self.output) + ".packaging-lock").mkdir()
        self.assertNotEqual(self.package().returncode, 0)
        self.assertTrue((self.output / "Contents/old-copy").exists())

    def test_reappearing_destination_preserves_backup(self):
        self.existing_app()
        self.mock("mv", 'case "$1" in */.Blinker-package.*/Blinker.app) mkdir -p "$2";; esac\n'
                        'exec /bin/mv "$@"')
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        backups = list(self.root.glob(".Blinker-package.*/previous.app/Contents/old-copy"))
        self.assertEqual(len(backups), 1)
        self.assertNotIn("packaged:", result.stdout)

    def test_success_replaces_only_after_verification(self):
        self.existing_app()
        self.mock("codesign", 'case "$1" in --verify) '
                             '[ -f "$EXPECTED_OLD" ] || exit 2;; esac\nexit 0')
        self.env["EXPECTED_OLD"] = str(self.output / "Contents/old-copy")
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.output / "Contents/MacOS/Blinker").exists())
        for name in ("LICENSE", "NOTICE"):
            self.assertEqual((self.output / "Contents/Resources" / name).read_bytes(),
                             (SCRIPT.parent.parent / name).read_bytes())
        self.assertFalse((self.output / "Contents/old-copy").exists())
        self.assertFalse(list(self.root.glob(".Blinker-package.*")))
        self.assertIn("packaged:", result.stdout)


if __name__ == "__main__":
    unittest.main()
