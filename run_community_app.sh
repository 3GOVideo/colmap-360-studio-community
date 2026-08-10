#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x "$APP_DIR/.venv/bin/python" ]]; then
  PYTHON="$APP_DIR/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
else
  echo "Python 3 no está instalado. Instálalo y vuelve a ejecutar este archivo."
  exit 1
fi

if ! "$PYTHON" -c 'import tkinter' >/dev/null 2>&1; then
  echo "Falta el componente gráfico Tk de Python."
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "En macOS ejecuta: brew install python-tk@3.12"
  else
    echo "En Ubuntu/Debian ejecuta: sudo apt install python3-tk"
  fi
  exit 1
fi

exec "$PYTHON" "$APP_DIR/cross_platform_app.py" "$@"
