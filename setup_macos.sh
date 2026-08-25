#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

if [[ "${1:-}" == "--venv" ]]; then
  [[ $# -ge 2 ]] || { echo "Falta la ruta para --venv" >&2; exit 2; }
  VENV_DIR="$2"
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "Revisando este Mac…"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew no está instalado. Instálalo una sola vez desde https://brew.sh y vuelve a pulsar ‘Preparar Mac’." >&2
  exit 1
fi

packages=()
command -v python3.12 >/dev/null 2>&1 || packages+=(python@3.12)
command -v ffmpeg >/dev/null 2>&1 || packages+=(ffmpeg)
command -v colmap >/dev/null 2>&1 || packages+=(colmap)
"$(command -v python3.12 || echo /usr/bin/false)" -c 'import tkinter' >/dev/null 2>&1 || packages+=(python-tk@3.12)

if [[ ${#packages[@]} -gt 0 ]]; then
  echo "Instalando: ${packages[*]}"
  brew install "${packages[@]}"
else
  echo "✓ Python, FFmpeg y COLMAP ya están disponibles."
fi

PYTHON_BIN="$(command -v python3.12 || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "No se encontró Python 3.12." >&2; exit 1; }

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "Creando el entorno privado de la app…"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

echo "Instalando o actualizando los componentes Python…"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install -r "$SCRIPT_DIR/requirements.txt"
"$VENV_DIR/bin/python" -c 'import tkinter, pycolmap, cv2, PIL, scipy, tqdm; print("✓ Interfaz, PyCOLMAP", pycolmap.__version__, "y OpenCV están listos.")'

SUPPORT_DIR="$(dirname "$VENV_DIR")"
BRUSH_DIR="$SUPPORT_DIR/Brush"
BRUSH_BIN="$BRUSH_DIR/brush_app"

if [[ ! -x "$BRUSH_BIN" ]]; then
  if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Brush oficial no ofrece actualmente un binario precompilado para este Mac Intel." >&2
    echo "Descárgalo manualmente desde https://github.com/ArthurBrussee/brush/releases/latest" >&2
    exit 1
  fi

  echo "Instalando Brush oficial para Apple Silicon…"
  BRUSH_TEMP="$(mktemp -d)"
  trap 'rm -rf "$BRUSH_TEMP"' EXIT
  curl --fail --location --retry 3 \
    "https://github.com/ArthurBrussee/brush/releases/latest/download/brush-app-aarch64-apple-darwin.tar.xz" \
    --output "$BRUSH_TEMP/brush.tar.xz"
  tar -xJf "$BRUSH_TEMP/brush.tar.xz" -C "$BRUSH_TEMP"
  DOWNLOADED_BRUSH="$(find "$BRUSH_TEMP" -type f -name brush_app -perm -111 -print -quit)"
  [[ -n "$DOWNLOADED_BRUSH" ]] || { echo "La descarga oficial no contenía brush_app." >&2; exit 1; }
  mkdir -p "$BRUSH_DIR"
  install -m 755 "$DOWNLOADED_BRUSH" "$BRUSH_BIN"
else
  echo "✓ Brush ya está instalado para COLMAP 360 Studio."
fi

echo "::brush-path $BRUSH_BIN"
echo "Preparación terminada."
