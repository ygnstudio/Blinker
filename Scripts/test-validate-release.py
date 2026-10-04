#!/usr/bin/env python3
"""Release tag and fail-closed artifact checks; no app launch or system changes."""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("validate-release.py").resolve()
SPEC = importlib.util.spec_from_file_location("release_check", SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
LICENSE_RESOURCES = ("LICENSE", "NOTICE", "ThirdParty/StatusTrio/LICENSE",
                     "ThirdParty/StatusTrio/NOTICE", "ThirdParty/StatusTrio/README.md",
                     "ThirdParty/MacbookDuoEffect/LICENSE", "ThirdParty/MacbookDuoEffect/README.md")


class VersionTests(unittest.TestCase):
    def test_stable_and_preview_channels_keep_exact_display_version(self):
        self.assertEqual(release.release_version("v1.2.3"), {
            "app_version": "1.2.3", "prerelease": "false", "make_latest": "true"})
        for channel in ("alpha", "beta", "rc"):
            tag = f"v0.4.0-{channel}.1"
            self.assertEqual(release.release_version(tag), {
                "app_version": tag[1:], "prerelease": "true", "make_latest": "false"})

    def test_invalid_or_ambiguous_tags_never_emit_workflow_outputs(self):
        for tag in ("1.2.3", "v1.2", "v01.2.3", "v1.2.3-beta", "v1.2.3-beta.0",
                    "v1.2.3-beta.01", "v1.2.3-preview.1", "v1.2.3+local", "v1.2.3\n",
                    "v1.2.3\nmake_latest=true", "v1.2.3;echo nope"):
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "outputs"
                result = subprocess.run(["python3", str(SCRIPT), "tag", tag,
                                         "--github-output", str(output)], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_cli_writes_validated_prerelease_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            result = subprocess.run(["python3", str(SCRIPT), "tag", "v0.4.0-beta.1",
                                     "--github-output", str(output)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(), "app_version=0.4.0-beta.1\n"
                             "prerelease=true\nmake_latest=false\n")


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="blinker-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.app = self.root / "Blinker.app"
        self.contents = self.app / "Contents"
        self.resources = self.contents / "Resources"
        self.core = self.resources / "Blinker_BlinkerCore.bundle/Contents"
        for name in LICENSE_RESOURCES:
            self.file(self.source / name, (name + " contents").encode())
            self.file(self.resources / name, (self.source / name).read_bytes())
        self.info = {"CFBundleIdentifier": "com.ygnstudio.Blinker", "CFBundleExecutable": "Blinker",
                     "CFBundleShortVersionString": "0.4.0-beta.1", "CFBundleVersion": "7",
                     "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "15.0"}
        self.write_info()
        self.file(self.contents / "MacOS/Blinker", b"test executable")
        (self.contents / "MacOS/Blinker").chmod(0o755)
        self.file(self.resources / "Blinker.icns", b"test icon")
        self.file(self.core / "Info.plist", plistlib.dumps({"CFBundlePackageType": "BNDL"}))
        for root in (self.resources, self.core / "Resources"):
            for language in ("en", "zh-Hans"):
                for name in ("Localizable.strings", "Localizable.stringsdict"):
                    self.file(root / f"{language}.lproj" / name, b"localized table")
        self.commands = []
        self.architectures = "arm64 x86_64"
        self.signature = "Signature=adhoc\n"
        self.fail_signing = False

    def file(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def write_info(self):
        self.file(self.contents / "Info.plist", plistlib.dumps(self.info))

    def run_tool(self, arguments):
        self.commands.append(arguments)
        if arguments[:2] == ["/usr/bin/lipo", "-archs"]:
            return self.architectures
        if arguments[:2] == ["/usr/bin/codesign", "--verify"] and self.fail_signing:
            raise subprocess.CalledProcessError(1, arguments)
        if arguments[:2] == ["/usr/bin/codesign", "--display"]:
            return self.signature
        if arguments[:2] == ["/usr/bin/hdiutil", "attach"]:
            mount = Path(arguments[arguments.index("-mountpoint") + 1])
            shutil.copytree(self.app, mount / "Blinker.app")
            (mount / "Applications").symlink_to("/Applications")
        return ""

    def verify(self):
        release.verify_app(self.app, "v0.4.0-beta.1", "7", self.source, self.run_tool)

    def test_complete_universal_adhoc_bundle_passes(self):
        self.verify()
        self.assertTrue(any(command[1] == "--verify" for command in self.commands))

    def test_missing_or_extra_architectures_fail(self):
        for architectures in ("arm64", "x86_64", "arm64 x86_64 arm64e", ""):
            with self.subTest(architectures=architectures):
                self.architectures = architectures
                with self.assertRaises(release.ValidationError):
                    self.verify()

    def test_version_identity_and_minimum_os_must_match(self):
        for key, value in (("CFBundleIdentifier", "com.ygnstudio.Blinker.dev"),
                           ("CFBundleShortVersionString", "0.4.0"), ("CFBundleVersion", "8"),
                           ("LSMinimumSystemVersion", "26.0"), ("CFBundleExecutable", "Other")):
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                self.write_info()
                with self.assertRaises(release.ValidationError):
                    self.verify()
                self.info[key] = original
        self.write_info()
        with self.assertRaises(release.ValidationError):
            release.verify_app(self.app, "v0.4.0-beta.1", "0", self.source, self.run_tool)

    def test_required_resources_cannot_be_missing_empty_or_symlinks(self):
        paths = [self.resources / name for name in LICENSE_RESOURCES]
        paths += [self.resources / "Blinker.icns", self.core / "Info.plist",
                  self.resources / "en.lproj/Localizable.strings",
                  self.core / "Resources/zh-Hans.lproj/Localizable.stringsdict"]
        for path in paths:
            with self.subTest(path=path):
                original = path.read_bytes()
                path.unlink()
                with self.assertRaises((OSError, release.ValidationError)):
                    self.verify()
                path.write_bytes(b"")
                with self.assertRaises(release.ValidationError):
                    self.verify()
                path.unlink()
                path.symlink_to(self.source / "LICENSE")
                with self.assertRaises(release.ValidationError):
                    self.verify()
                path.unlink()
                path.write_bytes(original)

    def test_changed_license_and_invalid_signature_fail(self):
        license_path = self.resources / "LICENSE"
        license_path.write_text("wrong license")
        with self.assertRaises(release.ValidationError):
            self.verify()
        license_path.write_bytes((self.source / "LICENSE").read_bytes())
        self.fail_signing = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.verify()
        self.fail_signing = False
        self.signature = "Authority=Developer ID Application: Example\n"
        with self.assertRaises(release.ValidationError):
            self.verify()

    def test_changed_third_party_notices_fail(self):
        for name in LICENSE_RESOURCES[2:]:
            with self.subTest(name=name):
                path = self.resources / name
                path.write_text("changed third-party notice")
                with self.assertRaises(release.ValidationError):
                    self.verify()
                path.write_bytes((self.source / name).read_bytes())

    def test_dmg_is_read_only_and_detached_when_app_validation_fails(self):
        dmg = self.root / "Blinker-v0.4.0-beta.1.dmg"
        dmg.write_bytes(b"test disk image")
        self.architectures = "arm64"
        with self.assertRaises(release.ValidationError):
            release.verify_dmg(dmg, "v0.4.0-beta.1", "7", self.source, self.run_tool)
        attach = next(command for command in self.commands if command[1] == "attach")
        self.assertIn("-readonly", attach)
        self.assertIn("-nobrowse", attach)
        self.assertEqual(self.commands[-1][1], "detach")

    def test_validation_failure_exits_without_creating_publishable_checksum(self):
        dmg = self.root / "Blinker-v0.4.0-beta.1.dmg"
        dmg.write_bytes(b"image")
        checksum = self.root / "SHA256SUMS.txt"
        arguments = ["dmg", str(dmg), "--tag", "v0.4.0-beta.1", "--build", "7",
                     "--checksums", str(checksum)]
        with patch.object(release, "verify_dmg", side_effect=release.ValidationError("bad artifact")):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(release.main(arguments), 1)
        self.assertFalse(checksum.exists())
        with patch.object(release, "verify_dmg"):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(release.main(arguments), 0)
        self.assertEqual(checksum.read_text(), f"{hashlib.sha256(b'image').hexdigest()}  {dmg.name}\n")


if __name__ == "__main__":
    unittest.main()
