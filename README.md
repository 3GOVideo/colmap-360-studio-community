# COLMAP 360 Rig Pipeline

![COLMAP 360 Studio](thumbnail-macos-app.png)

Turn equirectangular 360° frames into a COLMAP reconstruction that can be
opened directly in [Brush](https://github.com/ArthurBrussee/brush) for Gaussian
Splat training.

The pipeline follows COLMAP's official spherical-image workflow. Each panorama
is rendered as a fixed rig of perspective cameras, then processed through
feature extraction, feature matching, and incremental Structure-from-Motion.
The strongest reconstructed component is exported as a standard COLMAP dataset.

## Community desktop app — Windows, macOS, and Linux

`COLMAP 360 Studio Community` is the portable, unofficial interface. It checks
Python, the required Python modules, FFmpeg/FFprobe, COLMAP, and the independent
Brush application every time it starts. Missing required tools are shown in
red; Brush is optional, so a dataset can still be created before Brush is
installed. The interface also selects the video and output directory, estimates
frames, 360 virtual views and processing time, runs the pipeline, and keeps the
console as the only scrollable area.

After completing the installation steps below, start it with the launcher for
your operating system:

- **Windows:** double-click `run_community_app.bat`.
- **macOS:** double-click `run_community_app.command`.
- **Linux:** run `./run_community_app.sh`.

Brush is detected from the system `PATH` and common application folders. If it
was extracted elsewhere, use **Locate Brush…** or set the `BRUSH_PATH`
environment variable to its app or executable before launching this tool. Brush is developed independently;
this community interface is not affiliated with or endorsed by its authors.

### Self-contained installers

Packaged releases include Python, PyCOLMAP, OpenCV, FFmpeg, Pillow, SciPy, and
the remaining pipeline modules. End users do not need to install those
dependencies. Brush remains a separate download and is linked from the app's
**System configuration** section.

- macOS artifact: `COLMAP-360-Studio-Community-macOS.dmg`
- Windows artifact: `COLMAP-360-Studio-Community-Windows-Setup.exe`

Build locally on Apple Silicon macOS with:

```bash
python packaging/build_desktop.py --platform macos
```

The GitHub Actions workflow `.github/workflows/build-desktop.yml` builds each
artifact on its native operating system. PyInstaller does not cross-compile a
Windows executable from macOS.

## Visual macOS app

`COLMAP 360 Studio` adds a native graphical interface for people who prefer not
to use Terminal. It accepts `.mov` and `.mp4` videos, offers 1, 2, 5, or 10 FPS,
lets the user choose the result folder, displays live progress and logs, and
never overwrites an earlier job. After a video is selected, changing the FPS
updates the estimated total frames, 360 virtual views, and average processing
duration immediately.

- **360° video:** verifies the equirectangular 2:1 format and uses the official
  overlapping 12-camera rig before running COLMAP.
- **Flat video:** OpenCV measures sharpness and visual features, then COLMAP
  estimates camera poses and the sparse 3D model.
- **Frames only:** creates the image sequence without starting reconstruction.
- **Brush output:** full runs finish with a standard `brush-dataset` folder.

The app requires macOS 13 or newer. Build the local application with:

```bash
./build_macos_app.sh
```

Then open:

```text
dist/COLMAP 360 Studio.app
```

On first use, select **Prepare Mac**. The app checks Homebrew, Python 3.12,
FFmpeg, COLMAP, PyCOLMAP, and OpenCV, and installs missing supported components.
If Homebrew itself is missing, install it once from
[brew.sh](https://brew.sh), reopen the app, and select **Prepare Mac** again.

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
- Python Tcl/Tk graphical component (`python-tk@3.12` on Homebrew or
  `python3-tk` on Ubuntu/Debian)
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

## Interactive assistant for a 360° video

On macOS or Ubuntu/Debian, `run_360_video.sh` can prepare the computer and run
the complete workflow. Run it **from the folder containing the MP4 or MOV**:

```bash
cd "/path/to/folder-containing-the-video"
"/path/to/colmap-360-rig-pipeline/run_360_video.sh"
```

The assistant installs missing Python, FFmpeg, COLMAP, and Python packages;
detects the video; asks whether to extract 1, 2, or 5 frames per second; checks
the equirectangular 2:1 ratio; and asks whether to start reconstruction with the
12-camera overlapping rig. It never overwrites an existing frames or
reconstruction folder.

### Terminal explained for beginners (macOS and Linux)

Suppose the video folder and the downloaded tool are next to each other:

```text
colmap/
├── 360-sculpture/
│   └── my-video.mp4
└── colmap-360-rig-pipeline/
    └── run_360_video.sh
```

Open Terminal, paste the following commands one line at a time, and press
Enter after each line:

```bash
cd "/Users/your-name/Videos/colmap/360-sculpture"
"../colmap-360-rig-pipeline/run_360_video.sh"
```

- `cd` means **change directory**. It places Terminal inside the video folder.
- Quotes keep paths containing spaces together.
- `..` means **the parent folder**. From there, the second command enters the
  neighboring tool folder and runs `run_360_video.sh`.
- The script remains in its own folder. The current video folder is used for
  finding the MP4/MOV and saving the frames and reconstruction.

### Windows PowerShell (using WSL)

The interactive assistant is a Bash script, so Windows runs it through the
Windows Subsystem for Linux (WSL). Install WSL once by opening PowerShell as
Administrator and running:

```powershell
wsl --install
```

Restart Windows if requested. Then open PowerShell, enter WSL, move to the
folder containing the video, and run the tool:

```powershell
wsl
cd "/mnt/c/Users/your-name/Videos/colmap/360-sculpture"
"../colmap-360-rig-pipeline/run_360_video.sh"
```

In WSL, the Windows `C:\` drive appears as `/mnt/c/`. Replace `your-name` and
the example folders with the actual locations on the computer. The first run
may request the Windows/Linux administrator password while dependencies are
installed.

To extract frames without starting COLMAP:

```bash
"/path/to/colmap-360-rig-pipeline/run_360_video.sh" --frames-only
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

### Aplicación comunitaria — Windows, macOS y Linux

`COLMAP 360 Studio Community` es la nueva interfaz portable y no oficial. Cada
vez que inicia comprueba Python, los módulos necesarios de Python,
FFmpeg/FFprobe, COLMAP y la aplicación independiente Brush. Los componentes
obligatorios que falten aparecen en rojo. Brush se presenta como opcional, por
lo que el usuario puede generar el dataset aunque todavía no lo haya instalado.

La misma interfaz permite seleccionar el video y la carpeta de resultados,
escoger 1, 2, 5 o 10 FPS, ver el cálculo estimado de fotogramas, vistas
virtuales y duración, ejecutar el pipeline y revisar el registro. Únicamente el
registro de consola utiliza desplazamiento.

Después de realizar la instalación indicada más adelante, inicie la aplicación
con el archivo correspondiente:

- **Windows:** haga doble clic en `run_community_app.bat`.
- **macOS:** haga doble clic en `run_community_app.command`.
- **Linux:** ejecute `./run_community_app.sh`.

La aplicación busca Brush en el `PATH` y en las carpetas habituales de cada
sistema. Si Brush fue descomprimido en otra ubicación, pulse **Localizar
Brush…** o configure la variable de entorno `BRUSH_PATH` con la ruta de la
aplicación o del ejecutable antes de iniciar la herramienta. Brush es desarrollado de forma independiente; esta
interfaz comunitaria no está afiliada ni respaldada por sus autores.

#### Instaladores autónomos

Las versiones empaquetadas incluyen Python, PyCOLMAP, OpenCV, FFmpeg, Pillow,
SciPy y los demás módulos del pipeline. El usuario final no tiene que instalar
estas dependencias. Brush se mantiene como una descarga independiente y la
aplicación muestra su enlace en **Configuración del sistema**.

- Archivo para macOS: `COLMAP-360-Studio-Community-macOS.dmg`
- Instalador para Windows: `COLMAP-360-Studio-Community-Windows-Setup.exe`

En un Mac Apple Silicon se construye el DMG con:

```bash
python packaging/build_desktop.py --platform macos
```

El flujo `.github/workflows/build-desktop.yml` construye cada instalador en su
sistema operativo correspondiente. PyInstaller no permite compilar de forma
cruzada un ejecutable de Windows desde macOS.

### Aplicación visual para macOS

`COLMAP 360 Studio` permite usar la herramienta sin escribir comandos en
Terminal. La aplicación nativa acepta videos `.mov` y `.mp4`, permite escoger
1, 2, 5 o 10 FPS, elegir la carpeta de resultados y observar el avance y el
registro en tiempo real. Cada ejecución crea una carpeta nueva y nunca
sobrescribe trabajos anteriores. Después de seleccionar un video, cambiar los
FPS actualiza inmediatamente el total estimado de fotogramas, las vistas
virtuales 360 y la duración promedio del procesamiento.

- **Video 360°:** comprueba que el video equirectangular tenga relación 2:1 y
  usa el rig oficial superpuesto de 12 cámaras virtuales antes de ejecutar
  COLMAP.
- **Video plano:** OpenCV mide la nitidez y las características visuales;
  después COLMAP calcula las poses de cámara y el modelo 3D disperso.
- **Solo fotogramas:** genera la secuencia de imágenes sin iniciar COLMAP.
- **Salida para Brush:** una ejecución completa termina con una carpeta
  estándar llamada `brush-dataset`.

Se necesita macOS 13 o superior. Para construir la aplicación localmente:

```bash
./build_macos_app.sh
```

Después abra:

```text
dist/COLMAP 360 Studio.app
```

En el primer uso pulse **Preparar Mac**. La aplicación revisa Homebrew, Python
3.12, FFmpeg, COLMAP, PyCOLMAP y OpenCV, e instala los componentes compatibles
que falten. Si Homebrew todavía no existe en el computador, instálelo una sola
vez desde [brew.sh](https://brew.sh), vuelva a abrir la aplicación y pulse
**Preparar Mac** nuevamente.

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
- Componente gráfico Tcl/Tk de Python (`python-tk@3.12` mediante Homebrew o
  `python3-tk` en Ubuntu/Debian)
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

### Asistente interactivo para un video 360°

En macOS o Ubuntu/Debian puede usar `run_360_video.sh` para preparar el equipo
y ejecutar todo el proceso. Abra Terminal y sitúese **en la carpeta donde está
el archivo MP4 o MOV**, no en la carpeta del repositorio:

```bash
cd "/ruta/a/la-carpeta-que-contiene-el-video"
"/ruta/a/colmap-360-rig-pipeline/run_360_video.sh"
```

El asistente realiza las siguientes tareas:

1. Comprueba e instala, si hace falta, Python, FFmpeg, COLMAP y las dependencias
   de Python.
2. Busca archivos `.mp4` o `.mov` en la carpeta actual y permite seleccionar uno
   si encuentra varios.
3. Comprueba que el video tenga proporción equirectangular 2:1.
4. Pregunta si desea extraer 1, 2 o 5 fotogramas por segundo. Para una primera
   prueba se recomiendan 2 FPS.
5. Guarda los panoramas sin sobrescribir carpetas existentes.
6. Pregunta si desea iniciar COLMAP con el rig superpuesto de 12 cámaras
   virtuales, valida primero el dataset y solicita una confirmación final.
7. Al terminar, indica la carpeta `brush-dataset` que debe abrirse en Brush.

#### Explicación para principiantes: `cd` y el archivo `.sh`

Supongamos que la carpeta del video y la herramienta descargada están una al
lado de la otra:

```text
colmap/
├── 360-escultura/
│   └── mi-video.mp4
└── colmap-360-rig-pipeline/
    └── run_360_video.sh
```

Abra Terminal, copie estos comandos uno por uno y presione Enter después de
cada línea:

```bash
cd "/Users/su-nombre/Videos/colmap/360-escultura"
"../colmap-360-rig-pipeline/run_360_video.sh"
```

- `cd` significa **cambiar de carpeta**. Deja Terminal ubicada dentro de la
  carpeta que contiene el video.
- Las comillas hacen que una ruta con espacios se interprete completa.
- `..` significa **subir a la carpeta anterior**. Desde allí, el segundo
  comando entra en la carpeta vecina de la herramienta y ejecuta
  `run_360_video.sh`.
- No se entra dentro del archivo `.sh`: ese archivo es un programa que se
  ejecuta. El programa permanece en su propia carpeta, pero busca el video y
  guarda los resultados en la carpeta donde se ejecutó el primer `cd`.

#### Windows PowerShell mediante WSL

El asistente interactivo es un script Bash. Para ejecutarlo en Windows se usa
el Subsistema de Windows para Linux (WSL). Abra PowerShell como administrador,
ejecute este comando una sola vez y reinicie Windows si se lo solicita:

```powershell
wsl --install
```

Después, abra PowerShell normalmente, entre en WSL, cambie a la carpeta del
video y ejecute la herramienta:

```powershell
wsl
cd "/mnt/c/Users/su-nombre/Videos/colmap/360-escultura"
"../colmap-360-rig-pipeline/run_360_video.sh"
```

Dentro de WSL, el disco `C:\` de Windows aparece como `/mnt/c/`. Sustituya
`su-nombre` y las carpetas del ejemplo por las rutas reales. En la primera
ejecución, el sistema puede solicitar la contraseña de administrador para
instalar las dependencias.

Para extraer únicamente los frames y no iniciar COLMAP:

```bash
"/ruta/a/colmap-360-rig-pipeline/run_360_video.sh" --frames-only
```

Para ejecutar el asistente sin intentar instalar paquetes nuevos:

```bash
"/ruta/a/colmap-360-rig-pipeline/run_360_video.sh" --skip-install
```

El script nunca reemplaza automáticamente una carpeta de frames ni una
reconstrucción existente; si encuentra una, crea una ruta nueva con fecha y
hora.

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
