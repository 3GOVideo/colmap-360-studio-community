#!/usr/bin/env python3
"""Portable dependency discovery for COLMAP 360 Studio Community."""

from __future__ import annotations

import importlib.util
import json
import os
import platform
import shutil
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable

from runtime_support import ffmpeg_executable, is_frozen


BRUSH_DOWNLOAD_URL = "https://github.com/ArthurBrussee/brush/releases/latest"
SETTINGS_DIRECTORY = "COLMAP 360 Studio Community"


@dataclass(frozen=True)
class ToolStatus:
    name: str
    installed: bool
    location: str = ""
    detail: str = ""
    required: bool = True

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def _first_existing(paths: list[Path]) -> Path | None:
    for path in paths:
        try:
            if path.exists():
                return path.resolve()
        except OSError:
            continue
    return None


def find_executable(*names: str) -> str | None:
    for name in names:
        found = shutil.which(name)
        if found:
            return str(Path(found).resolve())
    return None


def settings_path() -> Path:
    system = platform.system()
    home = Path.home()
    if system == "Windows":
        base = Path(os.environ.get("LOCALAPPDATA") or home / "AppData/Local")
    elif system == "Darwin":
        base = home / "Library/Application Support"
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    return base / SETTINGS_DIRECTORY / "settings.json"


def saved_brush_path() -> str | None:
    try:
        data = json.loads(settings_path().read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    value = data.get("brush_path") if isinstance(data, dict) else None
    return value if isinstance(value, str) and value else None


def save_brush_path(path: str | Path) -> None:
    destination = settings_path()
    destination.parent.mkdir(parents=True, exist_ok=True)
    data: dict[str, object] = {}
    try:
        existing = json.loads(destination.read_text(encoding="utf-8"))
        if isinstance(existing, dict):
            data.update(existing)
    except (OSError, ValueError, TypeError):
        pass
    data["brush_path"] = str(Path(path).expanduser().resolve())
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(destination)


def find_brush() -> str | None:
    """Find the official Brush desktop/CLI binary without scanning the disk."""
    configured = os.environ.get("BRUSH_PATH") or saved_brush_path()
    if configured:
        found = _first_existing([Path(configured).expanduser()])
        if found:
            return str(found)
    command = find_executable(
        "brush", "brush-app", "brush_app", "brush.exe", "brush-app.exe", "brush_app.exe"
    )
    if command:
        return command

    home = Path.home()
    system = platform.system()
    candidates: list[Path] = []
    if system == "Darwin":
        for apps in (Path("/Applications"), home / "Applications"):
            candidates.extend(
                [
                    apps / "Brush.app",
                    apps / "brush.app",
                    apps / "brush-app.app",
                ]
            )
            try:
                candidates.extend(sorted(apps.glob("*Brush*.app")))
                candidates.extend(sorted(apps.glob("*brush*.app")))
            except OSError:
                pass
    elif system == "Windows":
        roots = [
            Path(os.environ.get("LOCALAPPDATA", "")),
            Path(os.environ.get("ProgramFiles", "")),
            Path(os.environ.get("ProgramFiles(x86)", "")),
            home / "Downloads",
        ]
        relative = [
            Path("Brush/brush.exe"),
            Path("Brush/brush-app.exe"),
            Path("Brush/brush_app.exe"),
            Path("Programs/Brush/brush.exe"),
            Path("Programs/Brush/brush-app.exe"),
            Path("Programs/Brush/brush_app.exe"),
            Path("brush-app-x86_64-pc-windows-msvc/brush.exe"),
            Path("brush-app-x86_64-pc-windows-msvc/brush-app.exe"),
            Path("brush-app-x86_64-pc-windows-msvc/brush_app.exe"),
        ]
        candidates.extend(root / item for root in roots if str(root) for item in relative)
    else:
        candidates.extend(
            [
                home / ".local/bin/brush",
                home / "Applications/brush",
                home / "Applications/brush-app",
                Path("/usr/local/bin/brush"),
                Path("/opt/brush/brush"),
                Path("/opt/brush/brush-app"),
            ]
        )
    found = _first_existing(candidates)
    return str(found) if found else None


def pycolmap_status() -> ToolStatus:
    supporting_modules = {
        "OpenCV": "cv2",
        "Pillow": "PIL",
        "SciPy": "scipy",
        "tqdm": "tqdm",
    }
    pycolmap_ready = importlib.util.find_spec("pycolmap") is not None
    missing = [
        label
        for label, module in supporting_modules.items()
        if importlib.util.find_spec(module) is None
    ]
    if not pycolmap_ready:
        missing.insert(0, "PyCOLMAP")
    if missing:
        return ToolStatus(
            "PyCOLMAP",
            False,
            sys.executable,
            "Faltan: " + ", ".join(missing),
        )
    try:
        import pycolmap
    except Exception as error:
        return ToolStatus(
            "PyCOLMAP",
            False,
            sys.executable,
            f"No se pudo cargar: {error}",
        )

    cuda_value = getattr(pycolmap, "has_cuda", False)
    cuda_ready = bool(cuda_value() if callable(cuda_value) else cuda_value)
    backend = "CUDA disponible" if cuda_ready else "CPU"
    return ToolStatus("PyCOLMAP", True, sys.executable, f"{backend} · OpenCV, Pillow, SciPy y tqdm incluidos")


def inspect_system(progress: Callable[[str], None] | None = None) -> list[ToolStatus]:
    def report(message: str) -> None:
        if progress is not None:
            progress(message)

    report("Comprobando Python…")
    python_detail = platform.python_version() + (" · incluido en la app" if is_frozen() else "")
    python_status = ToolStatus(
        "Python", sys.version_info >= (3, 11), sys.executable, python_detail
    )

    report("Cargando PyCOLMAP y las DLL de CUDA…")
    pycolmap = pycolmap_status()

    report("Buscando FFmpeg…")
    try:
        ffmpeg = ffmpeg_executable()
    except RuntimeError:
        ffmpeg = None

    report("Comprobando el motor COLMAP…")
    colmap = find_executable("colmap")
    pycolmap_ready = importlib.util.find_spec("pycolmap") is not None

    report("Buscando Brush…")
    brush = find_brush()

    report("Finalizando comprobación…")
    return [
        python_status,
        pycolmap,
        ToolStatus("FFmpeg", bool(ffmpeg), ffmpeg or "", "Incluido y listo" if ffmpeg else "No encontrado"),
        ToolStatus(
            "COLMAP",
            pycolmap_ready,
            colmap or sys.executable,
            "CLI disponible" if colmap else "Motor integrado mediante PyCOLMAP",
            required=False,
        ),
        ToolStatus(
            "Brush",
            bool(brush),
            brush or "",
            "Listo para entrenar" if brush else "Necesario para entrenar · usa el enlace de descarga",
            required=False,
        ),
    ]


def required_tools_ready(statuses: list[ToolStatus]) -> bool:
    return all(item.installed for item in statuses if item.required)


if __name__ == "__main__":
    import json

    print(json.dumps([item.to_dict() for item in inspect_system()], ensure_ascii=False, indent=2))
