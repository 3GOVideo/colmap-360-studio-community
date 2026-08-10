#!/usr/bin/env python3
"""Helpers shared by source and packaged COLMAP 360 Studio builds."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


def is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def ffmpeg_executable() -> str:
    """Return the bundled ImageIO FFmpeg binary or a system installation."""
    try:
        import imageio_ffmpeg

        candidate = Path(imageio_ffmpeg.get_ffmpeg_exe())
        if candidate.is_file():
            return str(candidate)
    except Exception:
        pass
    found = shutil.which("ffmpeg")
    if found:
        return found
    for prefix in (Path("/opt/homebrew/bin"), Path("/usr/local/bin")):
        candidate = prefix / "ffmpeg"
        if candidate.is_file():
            return str(candidate)
    raise RuntimeError("FFmpeg no está disponible dentro de la aplicación.")


def probe_video(video: Path) -> dict[str, object]:
    """Read dimensions and duration, preferring ffprobe and falling back to OpenCV."""
    ffprobe = shutil.which("ffprobe")
    if ffprobe:
        command = [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height:format=duration",
            "-of",
            "json",
            str(video),
        ]
        try:
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            data = json.loads(result.stdout)
            stream = data["streams"][0]
            return {
                "width": int(stream["width"]),
                "height": int(stream["height"]),
                "duration": float(data.get("format", {}).get("duration", 0) or 0),
            }
        except Exception:
            pass

    import cv2

    capture = cv2.VideoCapture(str(video))
    try:
        if not capture.isOpened():
            raise RuntimeError(f"No fue posible abrir el video: {video}")
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        source_fps = float(capture.get(cv2.CAP_PROP_FPS))
        frame_count = float(capture.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = frame_count / source_fps if source_fps > 0 else 0
        if width <= 0 or height <= 0:
            raise RuntimeError(f"No fue posible leer las dimensiones del video: {video}")
        return {"width": width, "height": height, "duration": duration}
    finally:
        capture.release()


def worker_command(worker: str, script: Path, arguments: list[str]) -> list[str]:
    """Dispatch back into the packaged executable or to a Python source file."""
    if is_frozen():
        return [sys.executable, worker, *arguments]
    return [sys.executable, str(script), *arguments]
