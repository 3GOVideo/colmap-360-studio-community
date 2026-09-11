#!/usr/bin/env python3
"""Run a small, deterministic PyCOLMAP CUDA extraction/matching smoke test."""

from __future__ import annotations

import argparse
import sqlite3
import tempfile
import time
from pathlib import Path

import numpy as np
import pycolmap


def count_rows(database: Path, table: str) -> int:
    with sqlite3.connect(database) as connection:
        return int(connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])


def create_fixture(images: Path) -> None:
    rng = np.random.default_rng(3605080)
    base = rng.integers(0, 256, size=(1200, 1600), dtype=np.uint8)
    yy, xx = np.ogrid[:1200, :1600]
    for index, shift in enumerate((0, 18, 36), 1):
        image = np.roll(base, shift=(shift // 2, shift), axis=(0, 1)).copy()
        circle = (xx - (420 + shift)) ** 2 + (yy - 520) ** 2 < 180**2
        image[circle] = 245
        image[180:260, 250 + shift : 850 + shift] = 20
        if not pycolmap.Bitmap.from_array(image).write(images / f"frame_{index:02d}.png"):
            raise RuntimeError("PyCOLMAP could not write the validation image")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", type=Path)
    args = parser.parse_args()

    if not pycolmap.has_cuda:
        raise SystemExit("FAIL: this PyCOLMAP build does not report CUDA support")

    temporary = None
    if args.workdir:
        root = args.workdir.resolve()
        root.mkdir(parents=True, exist_ok=True)
    else:
        # COLMAP's native worker pool can keep the SQLite file open briefly on
        # Windows after the test has completed. Cleanup must not turn a passed
        # GPU validation into a false failure.
        temporary = tempfile.TemporaryDirectory(
            prefix="pycolmap-cuda-", ignore_cleanup_errors=True
        )
        root = Path(temporary.name)

    images = root / "images"
    images.mkdir(exist_ok=True)
    database = root / "database.db"
    if database.exists():
        database.unlink()
    create_fixture(images)

    extraction = pycolmap.FeatureExtractionOptions()
    extraction.use_gpu = True
    extraction.gpu_index = "0"
    started = time.perf_counter()
    pycolmap.extract_features(
        database,
        images,
        camera_mode=pycolmap.CameraMode.SINGLE,
        extraction_options=extraction,
        device=pycolmap.Device.cuda,
    )
    extraction_seconds = time.perf_counter() - started

    matching = pycolmap.FeatureMatchingOptions()
    matching.use_gpu = True
    matching.gpu_index = "0"
    started = time.perf_counter()
    pycolmap.match_exhaustive(
        database,
        matching_options=matching,
        device=pycolmap.Device.cuda,
    )
    matching_seconds = time.perf_counter() - started

    keypoints = count_rows(database, "keypoints")
    matches = count_rows(database, "matches")
    geometries = count_rows(database, "two_view_geometries")
    if keypoints != 3 or matches == 0 or geometries == 0:
        raise SystemExit(
            f"FAIL: keypoint rows={keypoints}, match rows={matches}, "
            f"two-view geometries={geometries}"
        )

    print(f"PASS: PyCOLMAP {pycolmap.__version__} CUDA smoke test")
    print(f"Build: {pycolmap.COLMAP_build}")
    print(f"Feature extraction: {extraction_seconds:.3f} s")
    print(f"Feature matching: {matching_seconds:.3f} s")
    print(f"Database: {keypoints} images, {matches} match pairs, {geometries} geometries")
    if temporary is not None:
        temporary.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
