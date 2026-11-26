#!/usr/bin/env python3
"""Create a Brush-ready COLMAP model from conventional perspective frames."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import cv2
import pycolmap


IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"}
CAMERA_MODELS = (
    "SIMPLE_PINHOLE", "PINHOLE", "SIMPLE_RADIAL", "SIMPLE_RADIAL_FISHEYE",
    "RADIAL", "RADIAL_FISHEYE", "OPENCV", "OPENCV_FISHEYE", "FULL_OPENCV",
    "FOV", "THIN_PRISM_FISHEYE", "RAD_TAN_THIN_PRISM_FISHEYE",
    "SIMPLE_DIVISION", "DIVISION", "SIMPLE_FISHEYE", "FISHEYE", "EUCM",
)


def images_in(folder: Path) -> list[Path]:
    return sorted(p for p in folder.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES)


def analyze_images(paths: list[Path]) -> tuple[float, int]:
    blur_scores: list[float] = []
    feature_counts: list[int] = []
    detector = cv2.SIFT_create(nfeatures=4000)
    for index, path in enumerate(paths, 1):
        image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
        if image is None:
            continue
        preview_width = min(1600, image.shape[1])
        scale = preview_width / image.shape[1]
        preview = cv2.resize(image, None, fx=scale, fy=scale)
        blur_scores.append(float(cv2.Laplacian(preview, cv2.CV_64F).var()))
        feature_counts.append(len(detector.detect(preview, None)))
        if index % 25 == 0:
            print(f"OpenCV analizó {index}/{len(paths)} imágenes", flush=True)
    if not blur_scores:
        raise RuntimeError("OpenCV no pudo leer los fotogramas.")
    return sum(blur_scores) / len(blur_scores), round(sum(feature_counts) / len(feature_counts))


def choose_best(models: dict[int, pycolmap.Reconstruction]) -> pycolmap.Reconstruction:
    if not models:
        raise RuntimeError("COLMAP no produjo un modelo. Revisa solapamiento, movimiento y nitidez.")
    return max(models.values(), key=lambda m: (m.num_reg_images(), m.num_points3D()))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--images", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--matcher", choices=("sequential", "exhaustive"), default="sequential")
    parser.add_argument("--camera-model", choices=CAMERA_MODELS, default="OPENCV")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.images.expanduser().resolve()
    output = args.output.expanduser().resolve()
    paths = images_in(source)
    if len(paths) < 3:
        raise SystemExit("Se necesitan al menos 3 fotogramas para reconstruir.")
    if output.exists():
        raise SystemExit(f"La salida ya existe y no se sobrescribirá: {output}")

    output.mkdir(parents=True)
    images_dir = output / "images"
    try:
        images_dir.symlink_to(source, target_is_directory=True)
    except OSError:
        shutil.copytree(source, images_dir)

    blur, features = analyze_images(paths)
    print(f"OpenCV — nitidez media: {blur:.1f}; características medias: {features}", flush=True)
    database = output / "database.db"
    sparse = output / "sparse"
    sparse.mkdir()
    print(f"Modelo de cámara COLMAP: {args.camera_model}", flush=True)
    pycolmap.extract_features(
        database,
        images_dir,
        camera_mode=pycolmap.CameraMode.SINGLE,
        reader_options=pycolmap.ImageReaderOptions(camera_model=args.camera_model),
    )
    if args.matcher == "sequential":
        pycolmap.match_sequential(database)
    else:
        pycolmap.match_exhaustive(database)
    models = pycolmap.incremental_mapping(database, images_dir, sparse)
    best = choose_best(models)

    brush = output / "brush-dataset"
    brush_sparse = brush / "sparse" / "0"
    brush_sparse.mkdir(parents=True)
    best.write(brush_sparse)
    try:
        (brush / "images").symlink_to(images_dir, target_is_directory=True)
    except OSError:
        shutil.copytree(source, brush / "images")
    (brush / "README.txt").write_text(
        "Brush-ready COLMAP dataset from a conventional video.\n"
        f"Registered images: {best.num_reg_images()}\n"
        f"Sparse points: {best.num_points3D()}\n"
        f"OpenCV average sharpness: {blur:.1f}\n"
        f"OpenCV average detected features: {features}\n"
        f"COLMAP camera model: {args.camera_model}\n",
        encoding="utf-8",
    )
    print(f"Imágenes registradas: {best.num_reg_images()}", flush=True)
    print(f"Puntos 3D: {best.num_points3D()}", flush=True)
    print(f"Dataset para Brush: {brush}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
