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

Convierte fotogramas equirectangulares 360° en una reconstrucción COLMAP que se
puede abrir directamente en [Brush](https://github.com/ArthurBrussee/brush)
para entrenar Gaussian Splats.

El pipeline sigue el flujo oficial de COLMAP para imágenes esféricas. Cada
panorama se renderiza como un rig fijo de cámaras de perspectiva. Después se
ejecutan la extracción de características, el matching y la reconstrucción
incremental Structure-from-Motion. Finalmente, el componente reconstruido más
fuerte se exporta como un dataset COLMAP estándar compatible con Brush.

> **Resultado comprobado:** 239 panoramas de 7680 × 3840 produjeron 2.868
> imágenes de perspectiva. El procesamiento de COLMAP tardó aproximadamente
> 1 hora y 40 minutos usando CPU, y el entrenamiento en Brush produjo más de
> 4 millones de Gaussian Splats.

### ¿Por qué 12 cámaras virtuales?

La configuración superpuesta oficial de COLMAP 4.1.1 utiliza:

- 4 direcciones de yaw alrededor del panorama
- 3 ángulos de pitch: -35°, 0° y +35°
- 90° de campo visual horizontal y vertical

Esto crea `4 × 3 = 12` vistas de perspectiva superpuestas por panorama. Doce
es una configuración predeterminada robusta de COLMAP, pero no es un mínimo
universal documentado.

### Requisitos

- macOS, Windows 10/11 o Linux de 64 bits
- Python 3.11 o 3.12
- 16 GB de RAM como mínimo; 32 GB recomendados
- Al menos 15 GB de espacio libre; 30 GB recomendados para datasets grandes
- Panoramas con relación de aspecto exacta 2:1 y resolución consistente

El flujo usa PyCOLMAP directamente desde Python, por lo que no es obligatorio
instalar la aplicación de escritorio de COLMAP. Una distribución de PyCOLMAP
compatible con CUDA puede acelerar las operaciones soportadas; el paquete
estándar también puede ejecutar el proceso mediante CPU.

### Instalación en macOS o Linux

Clone primero el repositorio y entre en su carpeta:

```bash
git clone https://github.com/3GOVideo/colmap-360-rig-pipeline.git
cd colmap-360-rig-pipeline
```

Cree un entorno virtual e instale las dependencias:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### Instalación en Windows PowerShell

```powershell
git clone https://github.com/3GOVideo/colmap-360-rig-pipeline.git
cd colmap-360-rig-pipeline
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Si PowerShell bloquea la activación del entorno virtual, permita la ejecución
únicamente durante la sesión actual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

Compruebe que todas las dependencias estén instaladas:

```bash
python -c "import pycolmap, cv2, PIL, scipy, tqdm; print('OK', pycolmap.__version__)"
```

La salida esperada debe incluir `OK 4.1.1`.

### Preparar las imágenes

Puede crear una carpeta `360-images` junto a los scripts o indicar cualquier
otra ubicación mediante `--images`. Se admiten archivos JPG, JPEG, PNG, TIFF y
WebP.

```text
colmap-360-rig-pipeline/
├── reconstruct_360.py
├── panorama_sfm_4_1_1.py
└── 360-images/
    ├── frame_000001.jpg
    ├── frame_000002.jpg
    └── ...
```

Los panoramas deben tener una relación exacta 2:1; por ejemplo, 7680 × 3840 o
4096 × 2048. Todas las imágenes deben tener la misma resolución. Para frames
extraídos de video, los nombres deben ordenarse cronológicamente.

### Validar sin procesar

Ejecute primero `--dry-run`. Esta opción comprueba las rutas, cuenta los
panoramas y muestra cuántas vistas se generarán sin iniciar la reconstrucción.

```bash
python reconstruct_360.py \
  --images "/ruta/a/360-images" \
  --output "/ruta/a/360-reconstruction" \
  --dry-run
```

Ejemplo de salida para 239 panoramas:

```text
Input panoramas: 239
Expected perspective images: 2868
Output: /ruta/a/360-reconstruction
```

### Ejecutar la reconstrucción

Quite `--dry-run` para iniciar el pipeline completo:

```bash
python reconstruct_360.py \
  --images "/ruta/a/360-images" \
  --output "/ruta/a/360-reconstruction"
```

La configuración predeterminada utiliza matching secuencial y 12 vistas
superpuestas por panorama. Es la opción recomendada para frames extraídos de
un video.

Use matching exhaustivo solamente cuando las fotografías no tengan orden
temporal. Esta opción puede consumir mucho más tiempo y memoria:

```bash
python reconstruct_360.py \
  --images "/ruta/a/360-images" \
  --output "/ruta/a/360-reconstruction" \
  --matcher exhaustive
```

Para experimentar con 4 vistas sin solapamiento —más rápido, pero menos
robusto— use:

```bash
python reconstruct_360.py \
  --images "/ruta/a/360-images" \
  --output "/ruta/a/360-reconstruction" \
  --render-type perspective_non_overlapping
```

### Qué hace el pipeline

1. Renderiza cada panorama como 12 imágenes de perspectiva superpuestas.
2. Configura las vistas como cámaras pertenecientes a un único rig rígido.
3. Extrae características visuales mediante PyCOLMAP.
4. Relaciona características entre frames consecutivos o entre todas las
   imágenes, según el matcher seleccionado.
5. Ejecuta la reconstrucción incremental manteniendo fija la geometría del rig.
6. Selecciona el componente con más imágenes registradas y puntos 3D.
7. Crea automáticamente un dataset listo para Brush.

### Abrir el resultado en Brush

Cuando termine el proceso, abra en Brush la siguiente carpeta:

```text
360-reconstruction/brush-dataset
```

Esta contiene las imágenes de perspectiva renderizadas y el mejor modelo
COLMAP disperso en `sparse/0`, incluyendo `cameras.bin`, `images.bin`,
`points3D.bin`, `rigs.bin` y `frames.bin`.

En Windows, crear enlaces simbólicos puede requerir Modo de desarrollador o
permisos especiales. Si el enlace no se puede crear, el script copia las
imágenes automáticamente como alternativa portable; esto requiere espacio
adicional en disco.

### Advertencia de seguridad

El script se niega a sobrescribir una carpeta de salida existente. La opción
`--force` elimina permanentemente esa carpeta antes de comenzar nuevamente.
Utilícela únicamente después de comprobar cuidadosamente la ruta.

### Solución de problemas

| Problema | Solución |
|---|---|
| `No module named pycolmap` | Active `.venv` e instale `requirements.txt`. |
| `Only 360° panoramas are supported` | Exporte imágenes equirectangulares con relación exacta 2:1. |
| `Output already exists` | Elija otra ruta o use `--force` deliberadamente. |
| No se genera un modelo legible | Revise el orden de frames, desenfoque, solapamiento, iluminación y textura. |
| El proceso es demasiado lento | Use matching secuencial, cierre otras aplicaciones y considere una distribución compatible con GPU. |
| Brush no encuentra las imágenes en Windows | Active Modo de desarrollador o copie `images` dentro de `brush-dataset`. |
| Se registran pocas cámaras | Use más frames, mejor iluminación y la configuración superpuesta de 12 vistas. |

### Licencia y atribución

El código original de este repositorio se publica bajo la
[Licencia MIT](LICENSE). La implementación panorámica derivada de COLMAP
continúa sujeta a la licencia BSD de 3 cláusulas de COLMAP. Consulte
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) y [NOTICE](NOTICE).

El archivo adaptado corresponde al ejemplo oficial
[`panorama_sfm.py`](https://github.com/colmap/colmap/blob/4.1.1/python/examples/panorama_sfm.py).
Consulte también la
[documentación oficial de reconstrucción 360°](https://colmap.github.io/rigs.html#reconstruction-from-360-spherical-images).

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

Original code in this repository is released under the [MIT License](LICENSE).
The COLMAP-derived panorama implementation remains subject to COLMAP's BSD
3-Clause License; see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) and
[NOTICE](NOTICE).
