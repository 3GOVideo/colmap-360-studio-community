#!/usr/bin/env python3
"""Run the independent Brush CLI with Studio-friendly progress markers."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--brush", required=True, type=Path)
    parser.add_argument("--dataset", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--total-steps", type=int, default=30_000)
    parser.add_argument("--export-every", type=int, default=500)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def validate_dataset(dataset: Path) -> None:
    images = dataset / "images"
    sparse_candidates = (dataset / "sparse" / "0", dataset / "sparse")
    sparse = next(
        (
            folder
            for folder in sparse_candidates
            if (folder / "cameras.bin").is_file()
            and (folder / "images.bin").is_file()
            and (folder / "points3D.bin").is_file()
        ),
        None,
    )
    if not images.exists() or sparse is None:
        raise SystemExit(
            "El dataset debe contener images y sparse/0 con cameras.bin, "
            "images.bin y points3D.bin."
        )


def main() -> int:
    args = parse_args()
    brush = args.brush.expanduser().resolve()
    dataset = args.dataset.expanduser().resolve()
    output = args.output.expanduser().resolve()

    if not brush.is_file() or not os.access(brush, os.X_OK):
        raise SystemExit(f"Brush no es ejecutable: {brush}")
    if args.total_steps < 1 or args.export_every < 1:
        raise SystemExit("Los pasos y la frecuencia de exportación deben ser positivos.")
    validate_dataset(dataset)
    output.mkdir(parents=True, exist_ok=False)

    command = [
        str(brush),
        str(dataset),
        "--total-steps",
        str(args.total_steps),
        "--export-every",
        str(args.export_every),
        "--export-path",
        str(output),
        "--export-name",
        "splat_{iter}.ply",
    ]
    print(f"::brush-output {output}", flush=True)
    print(f"::brush-total-steps {args.total_steps}", flush=True)
    print("Configuración Brush: valores estándar; snapshots del visor cada "
          f"{args.export_every} pasos.", flush=True)
    print("$ " + subprocess.list2cmdline(command), flush=True)
    if args.dry_run:
        print("::brush-progress 1.0 Validación terminada", flush=True)
        return 0

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
    return process.wait()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
