#!/usr/bin/env python3
"""Build self-contained macOS and Windows community distributions."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "packaging"
BUILD = ROOT / "build-community"
DIST = ROOT / "dist-community"
APP_NAME = "COLMAP 360 Studio Community"
ICON_SOURCE = ROOT / "macos-app" / "Assets" / "app-icon.png"


def run(command: list[str]) -> None:
    print("$ " + subprocess.list2cmdline(command), flush=True)
    environment = os.environ.copy()
    environment["PYINSTALLER_CONFIG_DIR"] = str(BUILD / "pyinstaller-config")
    subprocess.run(command, cwd=ROOT, check=True, env=environment)


def reset_build_directories() -> None:
    for path in (BUILD, DIST):
        resolved = path.resolve()
        if resolved.parent != ROOT.resolve():
            raise RuntimeError(f"Unsafe build directory: {resolved}")
        if resolved.exists():
            shutil.rmtree(resolved)
        resolved.mkdir()


def create_windows_icon() -> Path:
    destination = PACKAGING / "AppIcon.ico"
    image = Image.open(ICON_SOURCE).convert("RGBA")
    image.save(destination, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    return destination


def create_macos_icon() -> Path:
    iconset = BUILD / "AppIcon.iconset"
    iconset.mkdir(parents=True)
    image = Image.open(ICON_SOURCE).convert("RGBA")
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        image.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)
    destination = PACKAGING / "AppIcon.icns"
    run([sys.executable, str(ROOT / "macos-app" / "make_icns.py"), str(iconset), str(destination)])
    return destination


def pyinstaller(icon: Path) -> None:
    separator = ";" if platform.system() == "Windows" else ":"
    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--windowed",
        "--onedir",
        "--name",
        APP_NAME,
        "--icon",
        str(icon),
        "--distpath",
        str(DIST),
        "--workpath",
        str(BUILD / "pyinstaller"),
        "--specpath",
        str(BUILD),
        "--collect-all",
        "pycolmap",
        "--collect-all",
        "imageio_ffmpeg",
        "--hidden-import",
        "process_video",
        "--hidden-import",
        "reconstruct_360",
        "--hidden-import",
        "reconstruct_flat",
        "--hidden-import",
        "panorama_sfm_4_1_1",
        "--hidden-import",
        "runtime_support",
        "--add-data",
        f"{ROOT / 'INSTALL_COMMUNITY.txt'}{separator}.",
        str(ROOT / "cross_platform_app.py"),
    ]
    run(command)


def build_macos_dmg() -> Path:
    app = DIST / f"{APP_NAME}.app"
    if not app.is_dir():
        raise RuntimeError(f"PyInstaller did not create {app}")
    run(["codesign", "--force", "--deep", "--sign", "-", str(app)])
    stage = BUILD / "dmg-root"
    stage.mkdir()
    shutil.copytree(app, stage / app.name, symlinks=True)
    shutil.copy2(ROOT / "INSTALL_COMMUNITY.txt", stage / "LEEME-README.txt")
    (stage / "Applications").symlink_to("/Applications")
    dmg = DIST / "COLMAP-360-Studio-Community-macOS.dmg"
    run([
        "hdiutil",
        "create",
        "-volname",
        APP_NAME,
        "-srcfolder",
        str(stage),
        "-ov",
        "-format",
        "UDZO",
        str(dmg),
    ])
    return dmg


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("macos", "windows"), required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    reset_build_directories()
    icon = create_macos_icon() if args.platform == "macos" else create_windows_icon()
    pyinstaller(icon)
    if args.platform == "macos":
        artifact = build_macos_dmg()
        print(f"DMG ready: {artifact}")
    else:
        executable = DIST / APP_NAME / f"{APP_NAME}.exe"
        if not executable.is_file():
            raise RuntimeError(f"PyInstaller did not create {executable}")
        print(f"Windows application ready: {executable}")
        print("Run Inno Setup with packaging/windows-installer.iss to create the installer.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
