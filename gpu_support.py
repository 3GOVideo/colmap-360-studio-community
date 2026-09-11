"""Shared PyCOLMAP compute selection with safe CUDA fallback."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, TypeVar

import pycolmap


T = TypeVar("T")
COMPUTE_CHOICES = ("auto", "cuda", "cpu")


@dataclass(frozen=True)
class ComputeBackend:
    mode: str
    device: pycolmap.Device
    use_gpu: bool
    gpu_index: str


def has_cuda() -> bool:
    value = getattr(pycolmap, "has_cuda", False)
    return bool(value() if callable(value) else value)


def select_backend(mode: str, gpu_index: str = "0") -> ComputeBackend:
    if mode not in COMPUTE_CHOICES:
        raise ValueError(f"Modo de cómputo no válido: {mode}")
    use_gpu = mode != "cpu" and has_cuda()
    if mode == "cuda" and not use_gpu:
        print("CUDA solicitado, pero PyCOLMAP no tiene CUDA; continuando en CPU.", flush=True)
    selected = "cuda" if use_gpu else "cpu"
    print(f"Aceleración COLMAP: {selected.upper()}" + (f" · GPU {gpu_index}" if use_gpu else ""), flush=True)
    return ComputeBackend(selected, pycolmap.Device.cuda if use_gpu else pycolmap.Device.cpu, use_gpu, gpu_index)


def run_with_fallback(
    label: str,
    backend: ComputeBackend,
    operation: Callable[[ComputeBackend], T],
) -> T:
    try:
        return operation(backend)
    except RuntimeError as error:
        if not backend.use_gpu:
            raise
        print(f"CUDA falló durante {label}: {error}", flush=True)
        print("Reintentando esta etapa en CPU…", flush=True)
        cpu = ComputeBackend("cpu", pycolmap.Device.cpu, False, backend.gpu_index)
        return operation(cpu)


def extraction_options(backend: ComputeBackend) -> pycolmap.FeatureExtractionOptions:
    options = pycolmap.FeatureExtractionOptions()
    options.use_gpu = backend.use_gpu
    options.gpu_index = backend.gpu_index
    return options


def matching_options(backend: ComputeBackend) -> pycolmap.FeatureMatchingOptions:
    options = pycolmap.FeatureMatchingOptions()
    options.use_gpu = backend.use_gpu
    options.gpu_index = backend.gpu_index
    return options
