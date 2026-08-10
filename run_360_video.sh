#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$PWD"
VENV_DIR="$SCRIPT_DIR/.venv"
FPS_CHOICE=""
VIDEO_CHOICE=""
SKIP_INSTALL=0
FRAMES_ONLY=0
ASSUME_YES=0

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf "%b\n" "${BLUE}→${RESET} $*"; }
success() { printf "%b\n" "${GREEN}✓${RESET} $*"; }
warn() { printf "%b\n" "${YELLOW}Aviso:${RESET} $*"; }
fail() { printf "%b\n" "${RED}Error:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  run_360_video.sh [opciones]

Ejecuta el asistente en la carpeta actual. Busca un video MP4 o MOV, extrae
fotogramas equirectangulares y, si se confirma, inicia COLMAP con el rig de
12 cámaras virtuales.

Opciones:
  --video RUTA       Seleccionar un video sin mostrar el menú.
  --fps 1|2|5|10     Elegir FPS sin mostrar la pregunta.
  --frames-only      Extraer frames y no ejecutar COLMAP.
  --skip-install     No instalar paquetes; solo comprobar dependencias.
  --yes              Confirmar automáticamente la reconstrucción.
  -h, --help         Mostrar esta ayuda.

Ejemplo desde la carpeta que contiene el video:
  /ruta/colmap-360-rig-pipeline/run_360_video.sh
EOF
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  local answer
  read -r -p "$prompt [s/N]: " answer
  case "$answer" in
    s|S|si|SI|sí|Sí|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video)
      [[ $# -ge 2 ]] || fail "--video necesita una ruta."
      VIDEO_CHOICE="$2"
      shift 2
      ;;
    --fps)
      [[ $# -ge 2 ]] || fail "--fps necesita 1, 2, 5 o 10."
      FPS_CHOICE="$2"
      shift 2
      ;;
    --frames-only)
      FRAMES_ONLY=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Opción desconocida: $1. Use --help."
      ;;
  esac
done

case "$FPS_CHOICE" in
  ""|1|2|5|10) ;;
  *) fail "FPS inválido: $FPS_CHOICE. Las opciones son 1, 2, 5 o 10." ;;
esac

printf "%b\n" "${BOLD}COLMAP 360° Video Assistant${RESET}"
printf "Carpeta de trabajo: %s\n" "$WORK_DIR"
printf "Herramienta: %s\n\n" "$SCRIPT_DIR"

install_macos_dependencies() {
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew no está instalado."
    if ! confirm "¿Desea instalar Homebrew desde su instalador oficial?"; then
      fail "Homebrew es necesario para instalar automáticamente las dependencias."
    fi
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  local packages=()
  command -v python3.12 >/dev/null 2>&1 || packages+=(python@3.12)
  command -v ffmpeg >/dev/null 2>&1 || packages+=(ffmpeg)
  command -v colmap >/dev/null 2>&1 || packages+=(colmap)
  command -v git >/dev/null 2>&1 || packages+=(git)

  if [[ ${#packages[@]} -gt 0 ]]; then
    info "Instalando con Homebrew: ${packages[*]}"
    brew install "${packages[@]}"
  else
    success "Python, FFmpeg, COLMAP y Git ya están disponibles."
  fi
}

install_linux_dependencies() {
  command -v apt-get >/dev/null 2>&1 || fail \
    "La instalación automática Linux actualmente soporta Ubuntu/Debian con apt."
  local sudo_cmd=()
  if [[ "$(id -u)" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || fail "Se necesita sudo para instalar paquetes."
    sudo_cmd=(sudo)
  fi
  info "Actualizando paquetes de Ubuntu/Debian..."
  "${sudo_cmd[@]}" apt-get update
  "${sudo_cmd[@]}" apt-get install -y \
    python3 python3-venv python3-pip ffmpeg colmap git
}

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  case "$(uname -s)" in
    Darwin) install_macos_dependencies ;;
    Linux) install_linux_dependencies ;;
    *) fail "Sistema no soportado por este instalador. Use macOS o Ubuntu/Debian." ;;
  esac
else
  info "Instalación omitida por --skip-install."
fi

PYTHON_BIN=""
if command -v python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3.12)"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
fi

[[ -n "$PYTHON_BIN" ]] || fail "No se encontró Python 3."
command -v ffmpeg >/dev/null 2>&1 || fail "No se encontró FFmpeg."
command -v ffprobe >/dev/null 2>&1 || fail "No se encontró FFprobe."
command -v colmap >/dev/null 2>&1 || warn \
  "No se encontró el comando COLMAP. El pipeline usa PyCOLMAP, pero se recomienda instalar COLMAP."

PYTHON_VERSION="$($PYTHON_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
  fail "Se necesita Python 3.11 o superior. Versión detectada: $PYTHON_VERSION"
fi
success "Python $PYTHON_VERSION detectado."
success "FFmpeg detectado: $(ffmpeg -version 2>/dev/null | head -n 1)"

[[ -f "$SCRIPT_DIR/reconstruct_360.py" ]] || fail "Falta reconstruct_360.py."
[[ -f "$SCRIPT_DIR/panorama_sfm_4_1_1.py" ]] || fail "Falta panorama_sfm_4_1_1.py."

resolve_video() {
  local selected=""
  if [[ -n "$VIDEO_CHOICE" ]]; then
    if [[ "$VIDEO_CHOICE" = /* ]]; then
      selected="$VIDEO_CHOICE"
    else
      selected="$WORK_DIR/$VIDEO_CHOICE"
    fi
    [[ -f "$selected" ]] || fail "El video no existe: $selected"
    printf "%s" "$selected"
    return
  fi

  shopt -s nullglob nocaseglob
  local videos=("$WORK_DIR"/*.mp4 "$WORK_DIR"/*.mov)
  shopt -u nocaseglob
  [[ ${#videos[@]} -gt 0 ]] || fail \
    "No se encontraron archivos .mp4 o .mov en $WORK_DIR"

  if [[ ${#videos[@]} -eq 1 ]]; then
    printf "%s" "${videos[0]}"
    return
  fi

  printf "\nVideos encontrados:\n" >&2
  local i
  for ((i=0; i<${#videos[@]}; i++)); do
    printf "  %d) %s\n" "$((i+1))" "$(basename "${videos[$i]}")" >&2
  done
  local selection
  while true; do
    read -r -p "Seleccione un video [1-${#videos[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && \
       (( selection >= 1 && selection <= ${#videos[@]} )); then
      printf "%s" "${videos[$((selection-1))]}"
      return
    fi
    warn "Selección inválida."
  done
}

VIDEO_PATH="$(resolve_video)"
VIDEO_NAME="$(basename "$VIDEO_PATH")"
VIDEO_STEM="${VIDEO_NAME%.*}"
success "Video seleccionado: $VIDEO_NAME"

VIDEO_INFO="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,avg_frame_rate:format=duration \
  -of default=noprint_wrappers=1 "$VIDEO_PATH")"
printf "%s\n" "$VIDEO_INFO"

WIDTH="$(printf "%s\n" "$VIDEO_INFO" | sed -n 's/^width=//p' | head -n 1)"
HEIGHT="$(printf "%s\n" "$VIDEO_INFO" | sed -n 's/^height=//p' | head -n 1)"
if [[ -n "$WIDTH" && -n "$HEIGHT" && "$WIDTH" -ne $((HEIGHT * 2)) ]]; then
  warn "El video mide ${WIDTH}x${HEIGHT}; se esperaba una relación equirectangular exacta 2:1."
  confirm "¿Desea continuar de todas formas?" || exit 0
fi

if [[ -z "$FPS_CHOICE" ]]; then
  printf "\nFrecuencia de extracción:\n"
  printf "  1) 1 FPS  - menos imágenes, proceso más rápido\n"
  printf "  2) 2 FPS  - recomendado para comenzar\n"
  printf "  5) 5 FPS  - más solapamiento, proceso más pesado\n"
  printf " 10) 10 FPS - máximo detalle, proceso mucho más pesado\n"
  while true; do
    read -r -p "¿Cuántos FPS desea extraer? [1/2/5/10]: " FPS_CHOICE
    case "$FPS_CHOICE" in
      1|2|5|10) break ;;
      *) warn "Escriba 1, 2, 5 o 10." ;;
    esac
  done
fi

FRAMES_DIR="$WORK_DIR/${VIDEO_STEM}-frames-${FPS_CHOICE}fps"
RECON_DIR="$WORK_DIR/${VIDEO_STEM}-colmap-${FPS_CHOICE}fps"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ -e "$FRAMES_DIR" ]]; then
  warn "La carpeta de frames ya existe; se usará una nueva para protegerla."
  FRAMES_DIR="${FRAMES_DIR}-${TIMESTAMP}"
fi
if [[ -e "$RECON_DIR" ]]; then
  warn "La carpeta de reconstrucción ya existe; se usará una nueva."
  RECON_DIR="${RECON_DIR}-${TIMESTAMP}"
fi

mkdir -p "$FRAMES_DIR"
info "Extrayendo frames a $FPS_CHOICE FPS..."
ffmpeg -hide_banner -i "$VIDEO_PATH" -vf "fps=$FPS_CHOICE" -q:v 2 \
  "$FRAMES_DIR/frame_%06d.jpg"

FRAME_COUNT="$(find "$FRAMES_DIR" -maxdepth 1 -type f -name '*.jpg' | wc -l | tr -d ' ')"
[[ "$FRAME_COUNT" -gt 0 ]] || fail "FFmpeg no generó imágenes."
success "Se generaron $FRAME_COUNT panoramas en: $FRAMES_DIR"
printf "Vistas virtuales esperadas: %d\n" "$((FRAME_COUNT * 12))"

if [[ "$FRAMES_ONLY" -eq 1 ]]; then
  success "Proceso finalizado en modo --frames-only."
  exit 0
fi

if ! confirm "¿Desea ejecutar ahora COLMAP con 12 cámaras virtuales por panorama?"; then
  printf "\nPara ejecutarlo después:\n"
  printf "cd %q\n" "$SCRIPT_DIR"
  printf "%q reconstruct_360.py --images %q --output %q\n" \
    "$VENV_DIR/bin/python" "$FRAMES_DIR" "$RECON_DIR"
  exit 0
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    fail "No existe el entorno Python $VENV_DIR. Ejecute otra vez sin --skip-install."
  fi
  info "Creando entorno virtual en $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

VENV_PYTHON="$VENV_DIR/bin/python"
if "$VENV_PYTHON" -c 'import pycolmap, cv2, PIL, scipy, tqdm' >/dev/null 2>&1; then
  success "Las dependencias Python ya están instaladas; no se descargarán de nuevo."
else
  if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    fail "Faltan dependencias Python. Ejecute otra vez sin --skip-install."
  fi
  info "Instalando las dependencias Python necesarias..."
  "$VENV_PYTHON" -m pip install -r "$SCRIPT_DIR/requirements.txt"
fi
"$VENV_PYTHON" -c \
  'import pycolmap, cv2, PIL, scipy, tqdm; print("Dependencias Python OK - PyCOLMAP", pycolmap.__version__)'

info "Validando el dataset antes de procesar..."
"$VENV_PYTHON" "$SCRIPT_DIR/reconstruct_360.py" \
  --images "$FRAMES_DIR" \
  --output "$RECON_DIR" \
  --dry-run

if ! confirm "¿Confirma iniciar la reconstrucción completa?"; then
  warn "Reconstrucción cancelada. Los frames se conservaron."
  exit 0
fi

printf "\nLa reconstrucción puede tardar. No cierre esta Terminal.\n"
START_TIME="$(date +%s)"
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -i "$VENV_PYTHON" "$SCRIPT_DIR/reconstruct_360.py" \
    --images "$FRAMES_DIR" \
    --output "$RECON_DIR"
else
  "$VENV_PYTHON" "$SCRIPT_DIR/reconstruct_360.py" \
    --images "$FRAMES_DIR" \
    --output "$RECON_DIR"
fi
END_TIME="$(date +%s)"
ELAPSED="$((END_TIME - START_TIME))"

success "Reconstrucción terminada en $((ELAPSED / 60)) min $((ELAPSED % 60)) s."
printf "Dataset para Brush:\n%s\n" "$RECON_DIR/brush-dataset"
