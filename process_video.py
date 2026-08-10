#!/usr/bin/env python3
"""Non-interactive video entry point used by the macOS application."""

from __future__ import annotations

import argparse
import subprocess
from datetime import datetime
from pathlib import Path

from runtime_support import ffmpeg_executable, is_frozen, probe_video, worker_command


PROJECT_DIR = Path(__file__).resolve().parent


def emit_progress(value: float, message: str) -> None:
    print(f"::progress {value:.2f} {message}", flush=True)


def run(command: list[str]) -> None:
    print("$ " + subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, check=True)


def unique_job_dir(output: Path, stem: str, kind: str, fps: int) -> Path:
    base = output / f"{stem}-{kind}-{fps}fps"
    if not base.exists():
        return base
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return output / f"{stem}-{kind}-{fps}fps-{timestamp}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--type", required=True, choices=("360", "flat"))
    parser.add_argument("--fps", required=True, type=int, choices=(1, 2, 5, 10))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--frames-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    video = args.video.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not video.is_file() or video.suffix.lower() not in {".mov", ".mp4"}:
        raise SystemExit(f"Selecciona un video MOV o MP4 válido: {video}")
    if not output.is_dir():
        output.mkdir(parents=True, exist_ok=True)

    info = probe_video(video)
    print(
        f"Video: {video.name} — {info['width']}×{info['height']} — "
        f"{info['duration']:.1f} s",
        flush=True,
    )
    if args.type == "360" and info["width"] != info["height"] * 2:
        raise SystemExit(
            "El modo 360 necesita un panorama equirectangular 2:1. "
            f"Este video mide {info['width']}×{info['height']}."
        )

    job = unique_job_dir(output, video.stem, args.type, args.fps)
    frames = job / "frames"
    reconstruction = job / "reconstruction"
    print(f"::output {job}", flush=True)
    emit_progress(0.04, "Preparando carpetas")
    if args.dry_run:
        print(f"Prueba correcta. La carpeta de trabajo sería: {job}")
        emit_progress(1, "Validación terminada")
        return 0

    frames.mkdir(parents=True)
    emit_progress(0.08, f"Extrayendo fotogramas a {args.fps} FPS")
    run([
        ffmpeg_executable(), "-hide_banner", "-nostdin", "-i", str(video),
        "-vf", f"fps={args.fps}", "-q:v", "2", str(frames / "frame_%06d.jpg"),
    ])
    frame_count = len(list(frames.glob("*.jpg")))
    if frame_count == 0:
        raise RuntimeError("FFmpeg no generó fotogramas.")
    print(f"Fotogramas guardados: {frame_count}", flush=True)
    emit_progress(0.22, f"Se extrajeron {frame_count} fotogramas")

    if args.frames_only:
        (job / "processing.log.note.txt").write_text(
            "Extracción terminada. No se solicitó reconstrucción COLMAP.\n",
            encoding="utf-8",
        )
        emit_progress(1, "Fotogramas listos")
        return 0

    if args.type == "360":
        emit_progress(0.28, "Creando el rig de 12 cámaras virtuales")
        program = PROJECT_DIR / "reconstruct_360.py"
        command = worker_command(
            "--reconstruct-360-worker",
            program,
            ["--images", str(frames), "--output", str(reconstruction)],
        )
    else:
        emit_progress(0.28, "Analizando nitidez y características visuales")
        program = PROJECT_DIR / "reconstruct_flat.py"
        command = worker_command(
            "--reconstruct-flat-worker",
            program,
            ["--images", str(frames), "--output", str(reconstruction)],
        )
    if not is_frozen() and not program.is_file():
        raise RuntimeError(f"Falta el motor de reconstrucción: {program.name}")
    run(command)
    emit_progress(1, "Dataset para Brush terminado")
    print(f"Dataset para Brush: {reconstruction / 'brush-dataset'}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"Un proceso terminó con código {error.returncode}.") from error
    except Exception as error:
        raise SystemExit(str(error)) from error
