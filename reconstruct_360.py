#!/usr/bin/env python3
"""Reconstruct equirectangular panoramas with COLMAP and prepare Brush input."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

import pycolmap

from runtime_support import is_frozen, run_relayed, worker_command


PROJECT_DIR = Path(__file__).resolve().parent
DEFAULT_INPUT = PROJECT_DIR / "360-images"
DEFAULT_OUTPUT = PROJECT_DIR / "360-reconstruction"
OFFICIAL_PIPELINE = PROJECT_DIR / "panorama_sfm_4_1_1.py"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"}


def image_files(folder: Path) -> list[Path]:
    return sorted(
        path
        for path in folder.rglob("*")
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    )


def choose_best_model(sparse_dir: Path) -> tuple[Path, pycolmap.Reconstruction]:
    candidates: list[tuple[int, int, Path, pycolmap.Reconstruction]] = []
    for model_dir in sparse_dir.iterdir():
        if not model_dir.is_dir():
            continue
        try:
            model = pycolmap.Reconstruction(model_dir)
        except Exception:
            continue
        candidates.append(
            (model.num_reg_images(), model.num_points3D(), model_dir, model)
        )
    if not candidates:
        raise RuntimeError(f"COLMAP produced no readable model in {sparse_dir}")
    _, _, model_dir, model = max(candidates, key=lambda item: (item[0], item[1]))
    return model_dir, model


def prepare_brush_dataset(output: Path) -> Path:
    best_dir, model = choose_best_model(output / "sparse")
    brush_dir = output / "brush-dataset"
    brush_sparse = brush_dir / "sparse" / "0"
    brush_sparse.mkdir(parents=True, exist_ok=True)
    model.write(brush_sparse)

    brush_images = brush_dir / "images"
    if not brush_images.exists():
        try:
            brush_images.symlink_to(Path("../images"), target_is_directory=True)
        except OSError:
            # Windows can restrict symlink creation. Copy as a portable fallback.
            shutil.copytree(output / "images", brush_images)

    (brush_dir / "README.txt").write_text(
        "Brush-ready COLMAP dataset\n"
        "===========================\n"
        "Open this directory in Brush. It contains perspective images and the "
        "best sparse COLMAP model.\n\n"
        f"Selected source model: {best_dir}\n"
        f"Registered images: {model.num_reg_images()}\n"
        f"Sparse points: {model.num_points3D()}\n",
        encoding="utf-8",
    )
    return brush_dir


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert 360 panoramas to a virtual camera rig, run COLMAP SfM, "
            "and prepare a Brush-compatible dataset."
        )
    )
    parser.add_argument("--images", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--compute", choices=("auto", "cuda", "cpu"), default="auto")
    parser.add_argument("--gpu-index", default="0")
    parser.add_argument(
        "--matcher", choices=("sequential", "exhaustive"), default="sequential"
    )
    parser.add_argument(
        "--render-type",
        choices=("perspective_overlapping", "perspective_non_overlapping"),
        default="perspective_overlapping",
        help="Overlapping produces 12 views per panorama and is more robust.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Delete an existing output directory before starting.",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Validate and print without running."
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.images.expanduser().resolve()
    output = args.output.expanduser().resolve()

    if not source.is_dir():
        raise SystemExit(f"Input folder does not exist: {source}")
    images = image_files(source)
    if not images:
        raise SystemExit(f"No supported images found in: {source}")
    if not is_frozen() and not OFFICIAL_PIPELINE.is_file():
        raise SystemExit(f"Missing version-matched pipeline: {OFFICIAL_PIPELINE}")
    if output.exists():
        if not args.force:
            raise SystemExit(
                f"Output already exists: {output}\n"
                "Choose another --output path or explicitly pass --force."
            )
        shutil.rmtree(output)

    command = worker_command(
        "--panorama-worker",
        OFFICIAL_PIPELINE,
        [
        "--input_image_path",
        str(source),
        "--output_path",
        str(output),
        "--matcher",
        args.matcher,
        "--mapper",
        "incremental",
        "--pano_render_type",
        args.render_type,
        "--compute",
        args.compute,
        "--gpu-index",
        args.gpu_index,
        ],
    )

    views_per_pano = 12 if args.render_type == "perspective_overlapping" else 4
    print(f"Input panoramas: {len(images)}")
    print(f"Expected perspective images: {len(images) * views_per_pano}")
    print(f"Output: {output}")
    print("Command:", subprocess.list2cmdline(command))
    if args.dry_run:
        return 0

    output.mkdir(parents=True)
    run_relayed(command)
    brush_dir = prepare_brush_dataset(output)
    _, model = choose_best_model(brush_dir / "sparse")
    print("\nReconstruction complete.")
    print(f"Registered perspective images: {model.num_reg_images()}")
    print(f"Sparse points: {model.num_points3D()}")
    print(f"Open this dataset in Brush: {brush_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
