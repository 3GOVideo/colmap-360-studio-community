#!/usr/bin/env python3
"""Cross-platform community GUI for the COLMAP 360 rig pipeline."""

from __future__ import annotations

import math
import os
import platform
import queue
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from runtime_support import is_frozen, probe_video
from system_check import BRUSH_DOWNLOAD_URL, ToolStatus, inspect_system, required_tools_ready


PROJECT_DIR = Path(__file__).resolve().parent
VIDEO_TYPES = (("360° equirectangular", "360"), ("Plano / convencional", "flat"))
FPS_VALUES = (1, 2, 5, 10)


def format_clock(seconds: float) -> str:
    seconds = max(0, int(round(seconds)))
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes}:{seconds:02d}"


def format_estimate(seconds: float) -> str:
    minutes = max(1, int(round(seconds / 60)))
    if minutes < 60:
        return f"≈ {minutes} min"
    hours, remainder = divmod(minutes, 60)
    return f"≈ {hours} h {remainder:02d} min"


class CommunityApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("COLMAP 360 Studio Community")
        self.root.geometry("1120x860")
        self.root.minsize(920, 720)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self.video_path = tk.StringVar()
        self.video_summary = tk.StringVar(value="Selecciona un video .mov o .mp4")
        self.video_type = tk.StringVar(value="360")
        self.fps = tk.IntVar(value=2)
        self.output_path = tk.StringVar(value=str(Path.home() / "Movies" if platform.system() == "Darwin" else Path.home() / "Videos"))
        self.reconstruct = tk.BooleanVar(value=True)
        self.estimate_frames = tk.StringVar(value="—")
        self.estimate_views = tk.StringVar(value="—")
        self.estimate_time = tk.StringVar(value="—")
        self.progress_text = tk.StringVar(value="Listo para comenzar")
        self.progress_value = tk.DoubleVar(value=0)
        self.system_summary = tk.StringVar(value="Comprobando este equipo…")
        self.video_info = {"width": 0, "height": 0, "duration": 0.0}
        self.statuses: list[ToolStatus] = []
        self.process: subprocess.Popen[str] | None = None
        self.messages: queue.Queue[tuple[str, object]] = queue.Queue()
        self.last_output: Path | None = None
        self.completed_signature: tuple[object, ...] | None = None
        self.brush_notice_shown = False

        self._configure_style()
        self._build_ui()
        self.fps.trace_add("write", lambda *_: self.update_estimate())
        self.video_type.trace_add("write", lambda *_: self.update_estimate())
        self.reconstruct.trace_add("write", lambda *_: self.update_estimate())
        self.root.after(100, self._drain_messages)
        self.refresh_system()
        if len(sys.argv) > 1:
            startup_video = Path(sys.argv[1]).expanduser()
            if startup_video.is_file() and startup_video.suffix.lower() in {".mov", ".mp4"}:
                self.root.after(250, lambda: self.set_video(startup_video))

    def _configure_style(self) -> None:
        style = ttk.Style(self.root)
        available = style.theme_names()
        if platform.system() == "Windows" and "vista" in available:
            style.theme_use("vista")
        elif "clam" in available and platform.system() == "Linux":
            style.theme_use("clam")
        style.configure("Title.TLabel", font=("TkDefaultFont", 22, "bold"))
        style.configure("Subtitle.TLabel", foreground="#68727d", font=("TkDefaultFont", 11))
        style.configure("Section.TLabel", font=("TkDefaultFont", 12, "bold"))
        style.configure("Metric.TLabel", font=("TkDefaultFont", 16, "bold"), foreground="#1479d1")
        style.configure("Primary.TButton", font=("TkDefaultFont", 12, "bold"), padding=(18, 10))
        style.configure("Status.TLabelframe", padding=8)
        style.configure("Status.TLabelframe.Label", font=("TkDefaultFont", 10, "bold"))

    def _build_ui(self) -> None:
        root = self.root
        root.columnconfigure(0, weight=1)
        root.rowconfigure(6, weight=1)

        header = ttk.Frame(root, padding=(22, 18, 22, 12))
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)
        ttk.Label(header, text="COLMAP 360 Studio Community", style="Title.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(header, text="De video a dataset para Gaussian Splat · proyecto comunitario no oficial", style="Subtitle.TLabel").grid(row=1, column=0, sticky="w", pady=(2, 0))
        ttk.Label(header, textvariable=self.system_summary).grid(row=0, column=1, sticky="e")
        ttk.Button(header, text="↻ Comprobar", command=self.refresh_system).grid(row=1, column=1, sticky="e", pady=(4, 0))

        self.tools_frame = ttk.Frame(root, padding=(22, 0, 22, 8))
        self.tools_frame.grid(row=1, column=0, sticky="ew")

        content = ttk.Frame(root, padding=(22, 4, 22, 8))
        content.grid(row=2, column=0, sticky="ew")
        content.columnconfigure(0, weight=1)

        ttk.Label(content, text="1. Video de entrada", style="Section.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 6))
        video_box = ttk.Frame(content, padding=10, relief="groove")
        video_box.grid(row=1, column=0, sticky="ew")
        video_box.columnconfigure(0, weight=1)
        ttk.Label(video_box, textvariable=self.video_path, font=("TkDefaultFont", 11, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(video_box, textvariable=self.video_summary, style="Subtitle.TLabel").grid(row=1, column=0, sticky="w", pady=(3, 0))
        self.select_video_button = ttk.Button(video_box, text="Seleccionar video…", command=self.choose_video)
        self.select_video_button.grid(row=0, column=1, rowspan=2, padx=(12, 0))

        ttk.Label(content, text="2. Procesamiento", style="Section.TLabel").grid(row=2, column=0, sticky="w", pady=(14, 6))
        processing = ttk.Frame(content, padding=10, relief="groove")
        processing.grid(row=3, column=0, sticky="ew")
        processing.columnconfigure(1, weight=1)
        ttk.Label(processing, text="Tipo de video").grid(row=0, column=0, sticky="w", padx=(0, 14))
        modes = ttk.Frame(processing)
        modes.grid(row=0, column=1, sticky="w")
        for index, (label, value) in enumerate(VIDEO_TYPES):
            ttk.Radiobutton(modes, text=label, value=value, variable=self.video_type).grid(row=0, column=index, padx=(0, 18))
        ttk.Label(processing, text="Fotogramas por segundo").grid(row=1, column=0, sticky="w", padx=(0, 14), pady=(9, 0))
        fps_frame = ttk.Frame(processing)
        fps_frame.grid(row=1, column=1, sticky="w", pady=(9, 0))
        for index, value in enumerate(FPS_VALUES):
            ttk.Radiobutton(fps_frame, text=f"{value} FPS", value=value, variable=self.fps).grid(row=0, column=index, padx=(0, 20))

        metrics = ttk.Frame(processing, padding=(10, 8))
        metrics.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(10, 6))
        for column in range(3):
            metrics.columnconfigure(column, weight=1)
        self._metric(metrics, 0, self.estimate_frames, "Fotogramas")
        self._metric(metrics, 1, self.estimate_views, "Vistas virtuales 360°")
        self._metric(metrics, 2, self.estimate_time, "Duración aproximada")
        ttk.Checkbutton(processing, text="Reconstruir con COLMAP y preparar para Brush", variable=self.reconstruct).grid(row=3, column=0, columnspan=2, sticky="w", pady=(4, 0))

        ttk.Label(content, text="3. Carpeta de resultados", style="Section.TLabel").grid(row=4, column=0, sticky="w", pady=(14, 6))
        output_box = ttk.Frame(content, padding=10, relief="groove")
        output_box.grid(row=5, column=0, sticky="ew")
        output_box.columnconfigure(0, weight=1)
        ttk.Label(output_box, textvariable=self.output_path).grid(row=0, column=0, sticky="w")
        self.output_button = ttk.Button(output_box, text="Cambiar…", command=self.choose_output)
        self.output_button.grid(row=0, column=1, padx=(12, 0))

        action = ttk.Frame(root, padding=(22, 4, 22, 10))
        action.grid(row=3, column=0, sticky="ew")
        action.columnconfigure(1, weight=1)
        self.cancel_button = ttk.Button(action, text="Cancelar", command=self.cancel, state="disabled")
        self.cancel_button.grid(row=0, column=0, sticky="w")
        ttk.Label(action, textvariable=self.progress_text).grid(row=0, column=1, sticky="e", padx=12)
        self.start_button = ttk.Button(action, text="✦ Crear dataset", style="Primary.TButton", command=self.start)
        self.start_button.grid(row=0, column=2, sticky="e")
        self.progress = ttk.Progressbar(action, maximum=1, variable=self.progress_value)
        self.progress.grid(row=1, column=0, columnspan=3, sticky="ew", pady=(8, 0))

        brush_actions = ttk.Frame(root, padding=(22, 0, 22, 8))
        brush_actions.grid(row=4, column=0, sticky="ew")
        ttk.Button(brush_actions, text="Localizar Brush…", command=self.locate_brush).pack(side="left")
        self.open_brush_button = ttk.Button(brush_actions, text="Abrir dataset en Brush", command=self.open_in_brush, state="disabled")
        self.open_brush_button.pack(side="left", padx=(8, 0))
        ttk.Label(brush_actions, text="Brush es un proyecto independiente; esta app no está afiliada con sus autores.", style="Subtitle.TLabel").pack(side="right")

        ttk.Label(root, text="Registro", style="Section.TLabel", padding=(22, 0, 22, 5)).grid(row=5, column=0, sticky="w")
        log_frame = ttk.Frame(root, padding=(22, 0, 22, 18))
        log_frame.grid(row=6, column=0, sticky="nsew")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log = tk.Text(log_frame, height=8, wrap="word", font=("TkFixedFont", 10), state="disabled")
        scroll = ttk.Scrollbar(log_frame, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        self.log.grid(row=0, column=0, sticky="nsew")
        scroll.grid(row=0, column=1, sticky="ns")
        self._set_controls()

    def _metric(self, parent: ttk.Frame, column: int, value: tk.StringVar, label: str) -> None:
        box = ttk.Frame(parent)
        box.grid(row=0, column=column, sticky="ew", padx=8)
        ttk.Label(box, textvariable=value, style="Metric.TLabel").pack(anchor="w")
        ttk.Label(box, text=label, style="Subtitle.TLabel").pack(anchor="w")

    def _signature(self) -> tuple[object, ...]:
        return (self.video_path.get(), self.video_type.get(), self.fps.get(), self.output_path.get(), self.reconstruct.get())

    def append_log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def refresh_system(self) -> None:
        self.system_summary.set("Comprobando este equipo…")
        threading.Thread(target=lambda: self.messages.put(("statuses", inspect_system())), daemon=True).start()

    def _show_statuses(self, statuses: list[ToolStatus]) -> None:
        self.statuses = statuses
        for child in self.tools_frame.winfo_children():
            child.destroy()
        ttk.Label(self.tools_frame, text="Configuración del sistema", style="Section.TLabel").grid(
            row=0, column=0, columnspan=len(statuses), sticky="w", pady=(0, 5)
        )
        for column, item in enumerate(statuses):
            self.tools_frame.columnconfigure(column, weight=1)
            card = ttk.LabelFrame(self.tools_frame, text=item.name, style="Status.TLabelframe")
            card.grid(row=1, column=column, sticky="nsew", padx=(0 if column == 0 else 5, 0))
            mark = "● Instalado" if item.installed else ("○ Descargar" if item.name == "Brush" else ("○ Opcional" if not item.required else "● Falta"))
            color = "#20a85a" if item.installed else ("#68727d" if not item.required else "#c23b32")
            tk.Label(card, text=mark, fg=color).pack(anchor="w")
            ttk.Label(card, text=item.detail, style="Subtitle.TLabel").pack(anchor="w")
            if item.name == "Brush" and not item.installed:
                ttk.Button(
                    card,
                    text="Descargar último release ↗",
                    command=lambda: webbrowser.open(BRUSH_DOWNLOAD_URL),
                ).pack(anchor="w", pady=(5, 0))
        required_ok = required_tools_ready(statuses)
        brush_ok = next((item.installed for item in statuses if item.name == "Brush"), False)
        self.system_summary.set("Equipo listo" if required_ok else "Faltan dependencias")
        self.open_brush_button.configure(state="normal" if brush_ok and self.last_output else "disabled")
        self._set_controls()
        if not brush_ok and not self.brush_notice_shown:
            self.brush_notice_shown = True
            self.root.after(
                350,
                lambda: messagebox.showinfo(
                    "Brush es necesario para entrenar",
                    "La creación del dataset funciona sin Brush. Para entrenar el Gaussian Splat, usa el botón de Configuración del sistema para abrir directamente el último release disponible.",
                ),
            )

    def choose_video(self) -> None:
        path = filedialog.askopenfilename(title="Selecciona un video", filetypes=[("Videos", "*.mov *.mp4"), ("Todos los archivos", "*.*")])
        if not path:
            return
        self.set_video(Path(path))

    def set_video(self, path: Path) -> None:
        path = path.expanduser().resolve()
        if not path.is_file() or path.suffix.lower() not in {".mov", ".mp4"}:
            self.append_log(f"Video no válido: {path}")
            return
        self.video_path.set(str(path))
        self.video_summary.set("Leyendo información del video…")
        self.completed_signature = None
        threading.Thread(target=self._probe_video, args=(path,), daemon=True).start()
        self._set_controls()

    def _probe_video(self, path: Path) -> None:
        try:
            self.messages.put(("probe", probe_video(path)))
        except Exception as error:
            self.messages.put(("probe_error", str(error)))

    def _apply_probe(self, info: dict[str, object]) -> None:
        self.video_info = info
        width, height, duration = int(info["width"]), int(info["height"]), float(info["duration"])
        panorama = width == height * 2
        if panorama:
            self.video_type.set("360")
        self.video_summary.set(f"{width} × {height} · {format_clock(duration)}" + (" · panorama 2:1 detectado" if panorama else ""))
        self.update_estimate()

    def update_estimate(self) -> None:
        duration = float(self.video_info.get("duration", 0) or 0)
        width = int(self.video_info.get("width", 0) or 0)
        height = int(self.video_info.get("height", 0) or 0)
        if duration <= 0:
            self.estimate_frames.set("—")
            self.estimate_views.set("—")
            self.estimate_time.set("—")
            self._set_controls()
            return
        frames = max(1, round(duration * self.fps.get()))
        views = frames * 12 if self.video_type.get() == "360" and self.reconstruct.get() else 0
        if not self.reconstruct.get():
            megapixels = width * height / 1_000_000
            seconds = max(5, duration * max(0.08, megapixels / 30))
        elif self.video_type.get() == "360":
            resolution_factor = max(0.08, width * height / (7680 * 3840))
            seconds = max(20, views * 2.1 * resolution_factor)
        else:
            resolution_factor = max(0.45, math.sqrt(width * height / (1280 * 720)))
            seconds = max(20, frames * 1.8 * resolution_factor)
        self.estimate_frames.set(f"{frames:,}".replace(",", "."))
        self.estimate_views.set(f"{views:,}".replace(",", ".") if views else "—")
        self.estimate_time.set(format_estimate(seconds))
        self.completed_signature = None
        self._set_controls()

    def choose_output(self) -> None:
        path = filedialog.askdirectory(title="Selecciona la carpeta de resultados", initialdir=self.output_path.get())
        if path:
            self.output_path.set(path)
            self.completed_signature = None
            self._set_controls()

    def locate_brush(self) -> None:
        path = filedialog.askopenfilename(
            title="Selecciona la aplicación o el ejecutable de Brush",
            filetypes=[("Aplicaciones y ejecutables", "*.app *.exe"), ("Todos los archivos", "*.*")],
        )
        if path:
            os.environ["BRUSH_PATH"] = path
            self.append_log(f"Brush seleccionado: {path}")
            self.refresh_system()

    def _set_controls(self) -> None:
        running = self.process is not None and self.process.poll() is None
        ready = bool(self.statuses) and required_tools_ready(self.statuses)
        has_video = bool(self.video_path.get()) and float(self.video_info.get("duration", 0) or 0) > 0
        completed = self.completed_signature == self._signature()
        self.start_button.configure(state="normal" if ready and has_video and not running and not completed else "disabled")
        self.cancel_button.configure(state="normal" if running else "disabled")
        state = "disabled" if running else "normal"
        self.select_video_button.configure(state=state)
        self.output_button.configure(state=state)

    def start(self) -> None:
        if not required_tools_ready(self.statuses):
            messagebox.showwarning("Faltan dependencias", "Instala los componentes marcados en rojo y vuelve a comprobar.")
            return
        video = Path(self.video_path.get())
        if self.video_type.get() == "360" and self.video_info["width"] != self.video_info["height"] * 2:
            if not messagebox.askyesno("El video no parece 360°", "La proporción no es 2:1. ¿Quieres procesarlo como panorama de todas formas?"):
                return
        pipeline_arguments = ["--video", str(video), "--type", self.video_type.get(), "--fps", str(self.fps.get()), "--output", self.output_path.get()]
        if not self.reconstruct.get():
            pipeline_arguments.append("--frames-only")
        if is_frozen():
            arguments = [sys.executable, "--pipeline-worker", *pipeline_arguments]
        else:
            arguments = [sys.executable, str(PROJECT_DIR / "process_video.py"), *pipeline_arguments]
        self.append_log("Iniciando: " + subprocess.list2cmdline(arguments))
        self.progress_value.set(0.01)
        self.progress_text.set("Procesando video…")
        self.last_output = None
        try:
            self.process = subprocess.Popen(arguments, cwd=PROJECT_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        except Exception as error:
            messagebox.showerror("No fue posible iniciar", str(error))
            self.process = None
            return
        self._set_controls()
        threading.Thread(target=self._read_process, daemon=True).start()

    def _read_process(self) -> None:
        assert self.process and self.process.stdout
        process = self.process
        for line in process.stdout:
            self.messages.put(("line", line.rstrip()))
        code = process.wait()
        self.messages.put(("finished", code))

    def _handle_line(self, line: str) -> None:
        if line.startswith("::progress "):
            parts = line.split(" ", 2)
            try:
                self.progress_value.set(float(parts[1]))
                self.progress_text.set(parts[2] if len(parts) > 2 else "Procesando…")
            except ValueError:
                pass
            return
        if line.startswith("::output "):
            self.last_output = Path(line.removeprefix("::output ").strip())
        self.append_log(line)

    def _finished(self, code: int) -> None:
        self.process = None
        if code == 0:
            self.progress_value.set(1)
            self.progress_text.set("Dataset terminado")
            self.completed_signature = self._signature()
            self.root.bell()
            self.root.deiconify()
            self.root.lift()
            self.root.attributes("-topmost", True)
            self.root.after(900, lambda: self.root.attributes("-topmost", False))
            messagebox.showinfo("Proceso terminado", f"El resultado quedó guardado en:\n{self.last_output or self.output_path.get()}")
        else:
            self.progress_text.set("El proceso terminó con un error")
            messagebox.showerror("Proceso incompleto", "Revisa las últimas líneas del registro.")
        brush_ok = next((item.installed for item in self.statuses if item.name == "Brush"), False)
        self.open_brush_button.configure(state="normal" if brush_ok and self.last_output else "disabled")
        self._set_controls()

    def cancel(self) -> None:
        if not self.process or self.process.poll() is not None:
            return
        self.append_log("Cancelación solicitada; se conservarán los archivos generados.")
        self.process.terminate()

    def open_in_brush(self) -> None:
        brush = next((item.location for item in self.statuses if item.name == "Brush" and item.installed), "")
        if not brush or not self.last_output:
            return
        dataset = self.last_output / "reconstruction" / "brush-dataset"
        if not dataset.exists():
            dataset = self.last_output
        try:
            if platform.system() == "Darwin" and brush.endswith(".app"):
                subprocess.Popen(["open", "-a", brush, str(dataset)])
            else:
                subprocess.Popen([brush, str(dataset)])
        except Exception as error:
            messagebox.showerror("No se pudo abrir Brush", str(error))

    def _drain_messages(self) -> None:
        try:
            while True:
                kind, payload = self.messages.get_nowait()
                if kind == "statuses":
                    self._show_statuses(payload)  # type: ignore[arg-type]
                elif kind == "probe":
                    self._apply_probe(payload)  # type: ignore[arg-type]
                elif kind == "probe_error":
                    self.video_summary.set("No fue posible leer el video")
                    self.append_log(f"Error leyendo el video: {payload}")
                elif kind == "line":
                    self._handle_line(str(payload))
                elif kind == "finished":
                    self._finished(int(payload))
        except queue.Empty:
            pass
        self.root.after(100, self._drain_messages)

    def close(self) -> None:
        if self.process and self.process.poll() is None:
            if not messagebox.askyesno("Hay un proceso activo", "¿Quieres cerrar la aplicación y detener el proceso?"):
                return
            self.process.terminate()
        self.root.destroy()


def main() -> int:
    root = tk.Tk()
    CommunityApp(root)
    root.mainloop()
    return 0


def run_packaged_worker() -> int | None:
    if len(sys.argv) < 2:
        return None
    worker = sys.argv[1]
    if worker not in {
        "--pipeline-worker",
        "--reconstruct-360-worker",
        "--reconstruct-flat-worker",
        "--panorama-worker",
    }:
        return None
    # Windowed PyInstaller builds may not initialize text streams. Popen still
    # supplies file descriptors 1 and 2, so wrap them for live progress logs.
    if sys.stdout is None:
        sys.stdout = os.fdopen(os.dup(1), "w", buffering=1)
    if sys.stderr is None:
        sys.stderr = os.fdopen(os.dup(2), "w", buffering=1)
    sys.argv = [worker, *sys.argv[2:]]
    if worker == "--pipeline-worker":
        from process_video import main as worker_main
    elif worker == "--reconstruct-360-worker":
        from reconstruct_360 import main as worker_main
    elif worker == "--reconstruct-flat-worker":
        from reconstruct_flat import main as worker_main
    else:
        from panorama_sfm_4_1_1 import main as worker_main
    return worker_main()


if __name__ == "__main__":
    worker_result = run_packaged_worker()
    raise SystemExit(main() if worker_result is None else worker_result)
