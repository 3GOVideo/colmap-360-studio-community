# COLMAP 360 Rig Pipeline

Turn equirectangular 360° frames into a COLMAP reconstruction that can be
opened directly in [Brush](https://github.com/ArthurBrussee/brush) for Gaussian
Splat training.

The pipeline follows COLMAP's official spherical-image workflow. Each panorama
is rendered as a fixed rig of perspective cameras, then processed through
feature extraction, feature matching, and incremental Structure-from-Motion.
The strongest reconstructed component is exported as a standard COLMAP dataset.

> **Proven result:** 239 panoramas at 7680 × 3840 produced 2,868 perspective
> images. COLMAP processing took about 1 hour 40 minutes on CPU, and the Brush
> training produced more than 4 million Gaussian splats.

## Why 12 virtual cameras?

The official COLMAP 4.1.1 overlapping preset uses:

- 4 yaw directions around the panorama
- 3 pitch angles: -35°, 0°, and +35°
- 90° horizontal and vertical field of view

That creates `4 × 3 = 12` overlapping perspective views per panorama. Twelve is
a robust upstream default, not a documented universal minimum.

## Requirements

- macOS, Windows 10/11, or Linux, 64-bit
- Python 3.11 or 3.12
- 16 GB RAM minimum; 32 GB recommended
- At least 15 GB free disk space; 30 GB recommended for large datasets
- Panoramas with an exact 2:1 aspect ratio and consistent resolution

The Python workflow uses PyCOLMAP, so the COLMAP desktop application is not
required. A CUDA-capable PyCOLMAP build can accelerate supported operations;
the standard package may run on CPU.

## Install

```bash
git clone https://github.com/3GOVideo/colmap-360-rig-pipeline.git
cd colmap-360-rig-pipeline
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Windows PowerShell activation:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## Prepare images

Either create a `360-images` folder beside the scripts or pass any image folder
with `--images`. Supported extensions are JPG, JPEG, PNG, TIFF, and WebP.

```text
colmap-360-rig-pipeline/
├── reconstruct_360.py
├── panorama_sfm_4_1_1.py
└── 360-images/
    ├── frame_000001.jpg
    ├── frame_000002.jpg
    └── ...
```

For video frames, make sure filenames sort in chronological order.

## Validate without processing

```bash
python reconstruct_360.py \
  --images "/path/to/360-images" \
  --output "/path/to/360-reconstruction" \
  --dry-run
```

## Run reconstruction

```bash
python reconstruct_360.py \
  --images "/path/to/360-images" \
  --output "/path/to/360-reconstruction"
```

The default is sequential matching with 12 overlapping views per panorama.
Use exhaustive matching only for unordered photographs:

```bash
python reconstruct_360.py \
  --images "/path/to/360-images" \
  --output "/path/to/360-reconstruction" \
  --matcher exhaustive
```

For a faster but less robust 4-view experiment:

```bash
python reconstruct_360.py \
  --images "/path/to/360-images" \
  --output "/path/to/360-reconstruction" \
  --render-type perspective_non_overlapping
```

## Open in Brush

After completion, open:

```text
360-reconstruction/brush-dataset
```

The directory contains the rendered perspective images and the best sparse
COLMAP model under `sparse/0`.

## Important safety note

The script refuses to overwrite an existing output directory. `--force`
permanently deletes that output directory before restarting, so use it only
when the path has been checked carefully.

## Troubleshooting

| Problem | Action |
|---|---|
| `No module named pycolmap` | Activate `.venv` and install `requirements.txt`. |
| `Only 360° panoramas are supported` | Export exact 2:1 equirectangular images. |
| `Output already exists` | Choose a new path, or deliberately use `--force`. |
| No readable model | Check frame order, blur, overlap, lighting, and scene texture. |
| Brush cannot find images on Windows | Enable Developer Mode or copy `images` into `brush-dataset`. |

## Español

Este repositorio convierte fotogramas equirectangulares 360° en 12 vistas de
perspectiva superpuestas por panorama. Las vistas se configuran como un rig
rígido, PyCOLMAP extrae y relaciona características, reconstruye la escena y
crea una carpeta lista para abrir en Brush.

Instalación rápida:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python reconstruct_360.py --images "/ruta/360-images" --output "/ruta/resultado"
```

En Windows active el entorno con `.\.venv\Scripts\Activate.ps1`.

## Attribution

The version-matched panorama implementation is derived from COLMAP's official
[`panorama_sfm.py`](https://github.com/colmap/colmap/blob/4.1.1/python/examples/panorama_sfm.py).
See the [COLMAP 360° reconstruction documentation](https://colmap.github.io/rigs.html#reconstruction-from-360-spherical-images).

## License

BSD 3-Clause. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
