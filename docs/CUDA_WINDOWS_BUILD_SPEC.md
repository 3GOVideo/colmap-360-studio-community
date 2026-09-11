# Spec: build CUDA propio para Windows

Estado: Fases A y B implementadas y validadas  
Objetivo inicial: acelerar COLMAP con una NVIDIA RTX 5080 de 16 GB sin romper la distribución CPU.  
Decisión: viable. Primero se validará el wheel Windows CUDA publicado por
`lyehe/build_gpu_colmap`; un build local queda como requisito de reproducibilidad,
no como bloqueo para la prueba inicial.

## 1. Alcance

Crear una variante Windows x64 de COLMAP 360 Studio Community que:

- incluya PyCOLMAP compilado con CUDA 12.8;
- use GPU para extracción y matching de características;
- detecte CUDA en tiempo de ejecución y vuelva a CPU si no está disponible;
- muestre el backend y la GPU seleccionada en la UI y en el log;
- produzca datasets equivalentes y compatibles con Brush;
- mantenga disponible el artefacto Windows CPU actual.

No forma parte de la primera entrega:

- portar `cv2.remap` a CUDA;
- reconstrucción densa/PatchMatch;
- acelerar Brush, que administra su propio backend GPU;
- exigir CUDA al usuario de la edición CPU.

## 2. Restricciones confirmadas

- La máquina objetivo tiene RTX 5080, Compute Capability 12.0, driver 591.86 y 16 GB de VRAM.
- CUDA Toolkit 12.8 y CMake 4.4.1 están instalados.
- Blackwell 12.0 requiere CUDA 12.8 o posterior para código nativo.
- El proyecto fija `pycolmap==4.1.1`.
- El wheel oficial `pycolmap` para Windows es CPU; los wheels CUDA oficiales se publican sólo para Linux.
- `lyehe/build_gpu_colmap` publica wheels comunitarios PyCOLMAP 4.1.1 para
  Windows `win_amd64`, Python 3.10–3.14, en variantes `+cuda` y `+cuda.cudss`.
- La revisión recomendada es `v4.1.1-1`: declara fuente idéntica al tag upstream
  4.1.1 (`a0d785fb`), incluye procedencia `build_info.json` y publica
  `SHA256SUMS.txt`.
- Poner `use_gpu=True` no basta: el módulo y sus dependencias deben estar compilados con CUDA.

## 3. Arquitectura propuesta

### 3.1 Artefactos

Publicar dos paquetes separados:

- `COLMAP-360-Studio-Community-Windows-CPU.zip`
- `COLMAP-360-Studio-Community-Windows-CUDA12.zip`

La variante CUDA incluirá el wheel comunitario validado —o uno reproducido por
el proyecto desde las mismas fuentes— y sólo las DLL redistribuibles necesarias.
No descargará componentes durante el primer uso.

### 3.2 Build reproducible

Agregar:

- `packaging/windows-cuda/build_pycolmap_cuda.ps1`
- `packaging/windows-cuda/build-info.json`
- `requirements-windows-cuda.txt`
- un modo `--variant windows-cuda` en `packaging/build_desktop.py` o un wrapper equivalente;
- un workflow manual/release en GitHub Actions que compile, genere checksums y adjunte procedencia.

Fijar en el script:

- commit/tag exacto de COLMAP/PyCOLMAP 4.1.1;
- commit de vcpkg;
- Visual Studio 2022 Build Tools;
- CUDA Toolkit 12.8;
- arquitectura CUDA `120-real;120-virtual` para la edición RTX 50;
- Python 3.12 x64, igual que la aplicación actual.

Si se decide soportar también RTX 20/30/40 en el mismo binario, añadir arquitecturas 75, 86 y 89 después de medir el incremento de tamaño. La primera prueba debe limitarse a `sm_120` para reducir tiempo y superficie de fallo.

### 3.3 Integración de ejecución

Crear un módulo pequeño, por ejemplo `gpu_support.py`, responsable de:

- consultar de forma segura `pycolmap.has_cuda`;
- identificar GPU y VRAM mediante NVML o `nvidia-smi`, sin convertirlos en requisitos duros;
- resolver `auto`, `cuda` o `cpu`;
- seleccionar `gpu_index="0"` por defecto en un equipo de una GPU;
- registrar por qué se eligió GPU o por qué se hizo fallback.

Aplicar la configuración en `reconstruct_360.py`, `panorama_sfm_4_1_1.py` y `reconstruct_flat.py`:

- `FeatureExtractionOptions.use_gpu = True`;
- `FeatureExtractionOptions.gpu_index = "0"`;
- `FeatureMatchingOptions.use_gpu = True`;
- `FeatureMatchingOptions.gpu_index = "0"`;
- pasar `Device.cuda` cuando la firma de PyCOLMAP 4.1.1 lo requiera.

El mapper incremental seguirá en CPU inicialmente. El bundle adjustment CUDA será una fase separada, porque requiere verificar cómo fue compilado Ceres/cuDSS y puede cambiar resultados, memoria y dependencias.

### 3.4 UI

Añadir al estado del sistema:

- `GPU: RTX 5080 · 16 GB`;
- `Aceleración COLMAP: CUDA 12.8` o `CPU`;
- selector `Automático / GPU / CPU`, con `Automático` como valor inicial;
- aviso no bloqueante cuando el usuario pide GPU y sólo existe backend CPU.

La selección se pasará a los workers con `--compute auto|cuda|cpu` y `--gpu-index 0`.

## 4. Fases de implementación

### Fase A — validación del wheel disponible

1. Reparar o recrear un entorno Python 3.12; los `.venv` actuales apuntan a una instalación eliminada.
2. Descargar de `v4.1.1-1` el wheel
   `pycolmap-4.1.1+cuda-cp312-cp312-win_amd64.whl`, su `build_info.json` y
   `SHA256SUMS.txt`.
3. Verificar SHA-256 antes de instalar y archivar la procedencia con el release.
4. Verificar importación, versión exacta y que `pycolmap.has_cuda` sea verdadero.
5. Ejecutar extracción y matching sobre un fixture pequeño mientras `nvidia-smi` confirma uso de GPU y VRAM.
6. Ejecutar el validador determinista publicado por el proyecto, revisándolo antes de usarlo.
7. Comprobar específicamente que el binario contiene código compatible con Blackwell `sm_120` o PTX utilizable. Si no lo contiene, pasar a la Fase A2.

Salida de fase: wheel verificado y probado en la RTX 5080. Si esta fase falla, no modificar el pipeline ni publicar una edición CUDA.

### Fase A2 — reproducción local, sólo si es necesaria

1. Auditar los scripts y commits de `lyehe/build_gpu_colmap`.
2. Reproducir el wheel desde el tag upstream 4.1.1 con VS 2022, CUDA 12.8 y `sm_120`.
3. Comparar configuración, dependencias y resultados con el artefacto publicado.
4. Conservar scripts, hashes, flags CMake y lista de DLL en el proyecto.

### Fase B — integración del pipeline

1. Implementar detección, selección y fallback.
2. Conectar opciones GPU en los flujos plano y 360.
3. Agregar argumentos de worker y mensajes de log.
4. Probar que el modo CPU conserva el comportamiento actual.

Completada el 2026-09-11:

- selector UI `Automático / GPU / CPU` conectado a todos los workers;
- argumentos `--compute` y `--gpu-index` disponibles en CLI;
- extracción y matching reciben opciones y dispositivo explícitos;
- `Automático` elige CUDA sólo cuando `pycolmap.has_cuda` es verdadero;
- una excepción CUDA durante una etapa provoca reintento automático en CPU;
- PyCOLMAP muestra `CUDA disponible` o `CPU` en el estado del sistema;
- smoke test GPU y prueba controlada del fallback completados.

### Fase C — empaquetado y UI

1. Empaquetar el wheel CUDA y sus DLL mediante PyInstaller.
2. Incorporar estado y selector GPU a la UI.
3. Validar el paquete en una máquina NVIDIA limpia sin Python ni CUDA Toolkit instalados.
4. Publicar CPU y CUDA como artefactos distintos.

Estado al 2026-09-11: la edición NVIDIA fue empaquetada y el worker del `.exe`
resultante ejecutó extracción y matching SIFT en GPU 0. Se generó el ZIP
`COLMAP-360-Studio-Community-Windows-NVIDIA-CUDA12.zip` (1,19 GiB), con
SHA-256 `c75b2b7cd5e7bfaaabe08f6dcce52b77e92c3f93430290c04628bbecd190e39d`.
Quedan pendientes la prueba en una máquina NVIDIA limpia y la publicación.

### Fase D — benchmark

Medir por separado:

- extracción FFmpeg;
- render de las 12 vistas;
- extracción SIFT;
- matching;
- mapper/bundle adjustment;
- tiempo total y pico de VRAM/RAM.

Usar el mismo video, FPS, commit y configuración en CPU y CUDA. No afirmar mejoras basadas sólo en utilización de GPU.

## 5. Criterios de aceptación

- El paquete CUDA arranca en Windows 11 sin Python preinstalado.
- Detecta la RTX 5080 y reporta CUDA activo antes de reconstruir.
- SIFT y matching muestran actividad GPU verificable.
- Si CUDA falla, el trabajo continúa en CPU y explica el motivo en el log.
- Un fixture 360 termina y genera `brush-dataset/sparse/0` e `images` legibles por Brush.
- La cantidad de imágenes registradas y puntos 3D no presenta una regresión material frente a CPU.
- Cancelación, progreso y persistencia de Brush siguen funcionando.
- El paquete CPU continúa pasando sus pruebas.
- El release contiene SHA-256, licencias de terceros y `build-info.json`.

## 6. Riesgos y mitigación

- **Wheel Windows comunitario:** verificar hashes y procedencia; revisar sus
  scripts; reproducirlo localmente antes de un release público si la política
  de suministro del proyecto así lo exige.
- **Incompatibilidad Blackwell:** usar CUDA 12.8 con cubin `sm_120` y PTX 12.0.
- **Paquete demasiado grande:** separar CPU/CUDA y auditar DLL antes de distribuir.
- **Ceres sin CUDA/cuDSS:** excluir bundle adjustment GPU de la primera entrega.
- **Diferencias de resultado SIFT:** comparar métricas de registro, no igualdad binaria.
- **Máquinas sin NVIDIA:** fallback automático y artefacto CPU independiente.
- **CI sin GPU:** compilar en CI, pero ejecutar la prueba funcional final en la RTX 5080.

## 7. Decisión de inicio

La Fase A fue completada el 2026-09-11 con el wheel
`pycolmap-4.1.1+cuda-cp312-cp312-win_amd64.whl` de `v4.1.1-1`.

- SHA-256 verificado:
  `216a4f04e2e4096a6b629e9583b67c9051552fa6f6371c23152e1782f294c529`.
- PyCOLMAP reportó `COLMAP 4.1.1`, commit `a0d785f`, `with CUDA` y
  `has_cuda=True`.
- La extracción creó el backend `SIFT GPU feature extractor`.
- El matching se enlazó explícitamente a `GPU device 0` y creó
  `SIFT GPU feature matcher`.
- El fixture produjo tres filas de keypoints, tres pares de matches y tres
  geometrías verificadas.
- No hubo error de cubin/PTX al ejecutar sobre la RTX 5080 Compute Capability
  12.0; la compatibilidad Blackwell queda demostrada por ejecución.

El validador reproducible está en
`packaging/windows-cuda/validate_pycolmap_cuda.py`.

Siguiente decisión: proceder con la Fase B. La Fase A2 ya no es necesaria para
compatibilidad; queda como trabajo posterior de cadena de suministro.

No iniciar cambios de UI ni pipeline hasta obtener esa evidencia.
