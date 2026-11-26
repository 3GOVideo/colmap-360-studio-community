#!/usr/bin/env python3
"""Non-interactive video entry point used by the macOS application."""

from __future__ import annotations

import argparse
import math
import subprocess
from datetime import datetime
from pathlib import Path

from runtime_support import ffmpeg_executable, is_frozen, probe_video, worker_command


PROJECT_DIR = Path(__file__).resolve().parent
CAMERA_MODELS = (
    "SIMPLE_PINHOLE", "PINHOLE", "SIMPLE_RADIAL", "SIMPLE_RADIAL_FISHEYE",
    "RADIAL", "RADIAL_FISHEYE", "OPENCV", "OPENCV_FISHEYE", "FULL_OPENCV",
    "FOV", "THIN_PRISM_FISHEYE", "RAD_TAN_THIN_PRISM_FISHEYE",
    "SIMPLE_DIVISION", "DIVISION", "SIMPLE_FISHEYE", "FISHEYE", "EUCM",
)


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
    dated = output / f"{base.name}-{timestamp}"
    candidate = dated
    index = 2
    while candidate.exists():
        candidate = output / f"{dated.name}-{index}"
        index += 1
    return candidate


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--type", required=True, choices=("360", "flat"))
    parser.add_argument("--fps", required=True, type=int, choices=(1, 2, 5, 10))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--camera-model", choices=CAMERA_MODELS, default="OPENCV")
    parser.add_argument("--trim-start", type=float, help="Inicio del tramo en segundos.")
    parser.add_argument("--trim-end", type=float, help="Fin del tramo en segundos.")
    parser.add_argument("--frames-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    video = args.video.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not video.is_file() or video.suffix.lower() not in {".mov", ".mp4"}:
        raise SystemExit(f"Selecciona un video MOV o MP4 válido: {video}")

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

    seek = []
    filters = f"fps={args.fps}"
    if args.trim_start is not None or args.trim_end is not None:
        duration = info["duration"]
        start = args.trim_start if args.trim_start is not None else 0.0
        end = args.trim_end if args.trim_end is not None else duration
        if not (math.isfinite(start) and math.isfinite(end) and 0 <= start < end <= duration):
            raise SystemExit("El recorte debe tener un inicio y fin válidos dentro del video.")
        if end - start + 1e-9 < 1 / args.fps:
            raise SystemExit(f"El tramo es demasiado corto para extraer un fotograma a {args.fps} FPS.")
        seek = ["-ss", f"{start:.9f}"]
        filters = f"trim=end={end - start:.9f},setpts=PTS-STARTPTS,fps={args.fps}:eof_action=pass"
        print(f"Tramo seleccionado: {start:.3f}–{end:.3f} s", flush=True)

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
        ffmpeg_executable(), "-hide_banner", "-nostdin", *seek, "-i", str(video),
        "-map", "0:v:0", "-vf", filters, "-q:v", "2", str(frames / "frame_%06d.jpg"),
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
            [
                "--images", str(frames),
                "--output", str(reconstruction),
                "--camera-model", args.camera_model,
            ],
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
