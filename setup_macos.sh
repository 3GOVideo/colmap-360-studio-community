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
echo "Preparación terminada."
