#!/usr/bin/env python3
"""Validate release tags and the actual app inside a read-only mounted DMG."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
LICENSE_RESOURCES = ("LICENSE", "NOTICE", "ThirdParty/StatusTrio/LICENSE",
                     "ThirdParty/StatusTrio/NOTICE", "ThirdParty/StatusTrio/README.md",
                     "ThirdParty/MacbookDuoEffect/LICENSE", "ThirdParty/MacbookDuoEffect/README.md")
TAG = re.compile(r"v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))"
                 r"(?:-(alpha|beta|rc)\.([1-9][0-9]*))?")


class ValidationError(Exception):
    pass


def release_version(tag):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValidationError("tag must be vX.Y.Z or vX.Y.Z-(alpha|beta|rc).N (N >= 1)")
    preview = match.group(2) is not None
    return {"app_version": tag[1:], "prerelease": str(preview).lower(),
            "make_latest": str(not preview).lower()}


def run_command(arguments):
    result = subprocess.run(arguments, check=True, capture_output=True, text=True)
    return result.stdout + result.stderr


def regular_file(path):
    if not stat.S_ISREG(path.lstat().st_mode) or path.stat().st_size == 0:
        raise ValidationError(f"missing, empty or non-regular resource: {path}")
    return path


def verify_app(app, tag, build, source_root=ROOT, run=run_command):
    version = release_version(tag)
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValidationError("build number must be a positive integer")
    if app.is_symlink() or not app.is_dir():
        raise ValidationError(f"not an application directory: {app}")
    # Resource symlinks could escape the mounted artifact or hide missing contents.
    if any(path.is_symlink() for path in app.rglob("*")):
        raise ValidationError("release app must not contain resource symlinks")
    contents = app / "Contents"
    info = plistlib.loads(regular_file(contents / "Info.plist").read_bytes())
    if not isinstance(info, dict):
        raise ValidationError("Info.plist must be a dictionary")
    expected = {"CFBundleIdentifier": "com.ygnstudio.Blinker", "CFBundleExecutable": "Blinker",
                "CFBundleShortVersionString": version["app_version"], "CFBundleVersion": build,
                "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "15.0"}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValidationError(f"{key}: expected {value!r}, got {info.get(key)!r}")
    binary = regular_file(contents / "MacOS/Blinker")
    if not os.access(binary, os.X_OK):
        raise ValidationError("Blinker executable is not executable")
    architectures = set(run(["/usr/bin/lipo", "-archs", str(binary)]).split())
    if architectures != {"arm64", "x86_64"}:
        raise ValidationError(f"expected arm64 + x86_64, got {sorted(architectures)}")
    resources = contents / "Resources"
    regular_file(resources / "Blinker.icns")
    for name in LICENSE_RESOURCES:
        if regular_file(resources / name).read_bytes() != (source_root / name).read_bytes():
            raise ValidationError(f"bundled {name} differs from this release's source")
    core = resources / "Blinker_BlinkerCore.bundle/Contents"
    plistlib.loads(regular_file(core / "Info.plist").read_bytes())
    for resource_root in (resources, core / "Resources"):
        for language in ("en", "zh-Hans"):
            for table in ("Localizable.strings", "Localizable.stringsdict"):
                regular_file(resource_root / f"{language}.lproj" / table)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    signature = run(["/usr/bin/codesign", "--display", "--verbose=4", str(app)])
    if "Signature=adhoc" not in signature.splitlines():
        raise ValidationError("release policy requires an ad-hoc signature")


def verify_dmg(dmg, tag, build, source_root=ROOT, run=run_command):
    release_version(tag)
    dmg = regular_file(dmg).resolve()
    run(["/usr/bin/hdiutil", "verify", str(dmg)])
    with tempfile.TemporaryDirectory(prefix="blinker-release-check-") as directory:
        mount = Path(directory) / "volume"
        mount.mkdir()
        run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
             "-mountpoint", str(mount), str(dmg)])
        try:
            applications = mount / "Applications"
            if not applications.is_symlink() or os.readlink(applications) != "/Applications":
                raise ValidationError("DMG must contain the /Applications install link")
            verify_app(mount / "Blinker.app", tag, build, source_root, run)
        finally:
            run(["/usr/bin/hdiutil", "detach", str(mount)])


def write_checksum(dmg, destination):
    # Called only after all mounted-artifact checks and detach succeed.
    digest = hashlib.sha256()
    with dmg.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    destination.write_text(f"{digest.hexdigest()}  {dmg.name}\n", encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    tag_parser = commands.add_parser("tag")
    tag_parser.add_argument("tag")
    tag_parser.add_argument("--github-output", type=Path)
    for command in ("app", "dmg"):
        command_parser = commands.add_parser(command)
        command_parser.add_argument("path", type=Path)
        command_parser.add_argument("--tag", required=True)
        command_parser.add_argument("--build", required=True)
        if command == "dmg":
            command_parser.add_argument("--checksums", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "tag":
            output = "".join(f"{key}={value}\n" for key, value in release_version(args.tag).items())
            if args.github_output:
                with args.github_output.open("a", encoding="utf-8") as file:
                    file.write(output)
            print(output, end="")
        elif args.command == "app":
            verify_app(args.path, args.tag, args.build)
            print(f"verified app: {args.path}")
        else:
            if args.path.name != f"Blinker-{args.tag}.dmg":
                raise ValidationError("DMG filename must match its release tag")
            verify_dmg(args.path, args.tag, args.build)
            write_checksum(args.path, args.checksums)
            print(f"verified DMG: {args.path}; checksum: {args.checksums}")
    except (ValidationError, OSError, ValueError, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        print(f"release validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
