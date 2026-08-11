@echo off
setlocal
set "APP_DIR=%~dp0"

if exist "%APP_DIR%tools\brush\brush_app.exe" (
  set "BRUSH_PATH=%APP_DIR%tools\brush\brush_app.exe"
)

if exist "%APP_DIR%.venv\Scripts\python.exe" (
  set "PYTHON_EXE=%APP_DIR%.venv\Scripts\python.exe"
  set "PYTHON_ARGS="
) else (
  where py >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_EXE=py"
    set "PYTHON_ARGS=-3"
  ) else (
    where python >nul 2>nul
    if errorlevel 1 (
      echo Python 3 no esta instalado. Instalalo desde https://www.python.org/downloads/
      pause
      exit /b 1
    )
    set "PYTHON_EXE=python"
    set "PYTHON_ARGS="
  )
)

"%PYTHON_EXE%" %PYTHON_ARGS% -c "import tkinter" >nul 2>nul
if errorlevel 1 (
  echo La instalacion de Python no incluye el componente grafico Tcl/Tk.
  echo Reinstala Python desde https://www.python.org/downloads/ y activa la opcion Tcl/Tk.
  pause
  exit /b 1
)

"%PYTHON_EXE%" %PYTHON_ARGS% "%APP_DIR%cross_platform_app.py" %*
if errorlevel 1 pause
endlocal
