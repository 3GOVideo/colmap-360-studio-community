import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum VideoType: String {
    case panorama = "360"
    case flat

    var detail: String {
        switch self {
        case .panorama: return "Convierte cada panorama en el rig superpuesto de 12 cámaras virtuales."
        case .flat: return "OpenCV analiza nitidez y puntos visuales; COLMAP calcula cámaras y geometría."
        }
    }
}

enum COLMAPCameraModel: String, CaseIterable, Identifiable {
    case simplePinhole = "SIMPLE_PINHOLE"
    case pinhole = "PINHOLE"
    case simpleRadial = "SIMPLE_RADIAL"
    case simpleRadialFisheye = "SIMPLE_RADIAL_FISHEYE"
    case radial = "RADIAL"
    case radialFisheye = "RADIAL_FISHEYE"
    case opencv = "OPENCV"
    case opencvFisheye = "OPENCV_FISHEYE"
    case fullOpenCV = "FULL_OPENCV"
    case fov = "FOV"
    case thinPrismFisheye = "THIN_PRISM_FISHEYE"
    case radTanThinPrismFisheye = "RAD_TAN_THIN_PRISM_FISHEYE"
    case simpleDivision = "SIMPLE_DIVISION"
    case division = "DIVISION"
    case simpleFisheye = "SIMPLE_FISHEYE"
    case fisheye = "FISHEYE"
    case eucm = "EUCM"

    var id: String { rawValue }
}

enum DependencyState {
    case checking, ready, missing, unknown

    var label: String {
        switch self {
        case .checking: return "Revisando…"
        case .ready: return "Mac listo"
        case .missing: return "Faltan componentes"
        case .unknown: return "Sin revisar"
        }
    }
    var icon: String {
        switch self {
        case .checking: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .missing: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .ready: return .green
        case .missing: return .orange
        default: return .secondary
        }
    }
}

enum BrushTrainingState {
    case unavailable, ready, running, completed, failed

    var label: String {
        switch self {
        case .unavailable: return "Brush no localizado"
        case .ready: return "Listo para entrenar"
        case .running: return "Entrenando Gaussian Splat"
        case .completed: return "Entrenamiento terminado"
        case .failed: return "El entrenamiento se detuvo"
        }
    }

    var icon: String {
        switch self {
        case .unavailable: return "exclamationmark.triangle"
        case .ready: return "checkmark.circle"
        case .running: return "waveform.path.ecg"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .unavailable: return .orange
        case .ready: return .blue
        case .running: return .cyan
        case .completed: return .green
        case .failed: return .red
        }
    }
}

private struct JobConfiguration: Equatable {
    let videoPath: String
    let outputPath: String
    let videoType: VideoType
    let fps: Int
    let reconstruct: Bool
    let cameraModel: COLMAPCameraModel
}

@MainActor
final class PipelineController: NSObject, ObservableObject {
    private static let brushExecutablePathKey = "BrushExecutablePath"
    private static let brushTotalStepsKey = "BrushTotalSteps"
    static let brushMinimumSteps = 1_000
    static let brushMaximumSteps = 30_000

    @Published var videoURL: URL?
    @Published var outputURL: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
    @Published var videoType: VideoType = .panorama
    @Published var fps = 2
    @Published var reconstruct = true
    @Published var cameraModel: COLMAPCameraModel = {
        guard let saved = UserDefaults.standard.string(forKey: "COLMAPCameraModel"),
              let model = COLMAPCameraModel(rawValue: saved) else { return .opencv }
        return model
    }() {
        didSet { UserDefaults.standard.set(cameraModel.rawValue, forKey: "COLMAPCameraModel") }
    }
    @Published var isRunning = false
    @Published var progress = 0.0
    @Published var statusText = "Listo para comenzar"
    @Published var logText = ""
    @Published var videoSummary = "MOV o MP4 · el modo 360 espera una imagen 2:1"
    @Published private(set) var videoDuration = 0.0
    @Published private(set) var videoWidth = 0
    @Published private(set) var videoHeight = 0
    @Published var dependencyState: DependencyState = .unknown
    @Published var lastOutputURL: URL?
    @Published var brushState: BrushTrainingState = .unavailable
    @Published var brushDatasetURL: URL?
    @Published var brushOutputURL: URL?
    @Published var latestSplatURL: URL?
    @Published var brushExecutableURL: URL?
    @Published var brushLogText = ""
    @Published var brushProgress = 0.0
    @Published var brushStep = 0
    @Published var brushSplatCount: Int?
    @Published var previewPointCount = 0
    @Published var previewMilestoneLabel = ""
    @Published var isBrushRunning = false

    @Published var brushTotalSteps: Int = {
        let saved = UserDefaults.standard.integer(forKey: PipelineController.brushTotalStepsKey)
        guard saved > 0 else { return PipelineController.brushMaximumSteps }
        return min(max(saved, PipelineController.brushMinimumSteps), PipelineController.brushMaximumSteps)
    }() {
        didSet {
            if brushStepsAreValid {
                UserDefaults.standard.set(brushTotalSteps, forKey: Self.brushTotalStepsKey)
            }
        }
    }
    let brushExportEvery = 500

    private var process: Process?
    private var logHandle: FileHandle?
    private var bufferedOutput = ""
    private var activityToken: NSObjectProtocol?
    private var completedConfiguration: JobConfiguration?
    private var brushProcess: Process?
    private var brushLogHandle: FileHandle?
    private var brushBufferedOutput = ""
    private var brushMonitor: Timer?
    private var brushActivityToken: NSObjectProtocol?
    private var brushViewerProcess: Process?
    private var shownPreviewMilestones = Set<Int>()

    private var currentConfiguration: JobConfiguration? {
        guard let videoURL else { return nil }
        return JobConfiguration(
            videoPath: videoURL.path,
            outputPath: outputURL.path,
            videoType: videoType,
            fps: fps,
            reconstruct: reconstruct,
            cameraModel: cameraModel
        )
    }

    var hasCompletedCurrentConfiguration: Bool {
        currentConfiguration != nil && currentConfiguration == completedConfiguration
    }

    var canStart: Bool {
        currentConfiguration != nil && !isRunning && !isBrushRunning && !hasCompletedCurrentConfiguration
    }

    var canStartBrush: Bool {
        brushExecutableURL != nil && resolvedBrushDatasetURL != nil && brushStepsAreValid && !isRunning && !isBrushRunning
    }

    var brushStepsAreValid: Bool {
        (Self.brushMinimumSteps...Self.brushMaximumSteps).contains(brushTotalSteps)
    }

    var brushProgressPercent: Int {
        min(100, max(0, Int((brushProgress * 100).rounded())))
    }

    var resolvedBrushDatasetURL: URL? {
        if let brushDatasetURL, isBrushDataset(brushDatasetURL) { return brushDatasetURL }
        guard let lastOutputURL else { return nil }
        let candidates = [
            lastOutputURL.appendingPathComponent("reconstruction/brush-dataset"),
            lastOutputURL.appendingPathComponent("brush-dataset"),
            lastOutputURL,
        ]
        return candidates.first(where: isBrushDataset)
    }

    var estimatedFrameCount: Int {
        guard videoDuration > 0 else { return 0 }
        return max(1, Int((videoDuration * Double(fps)).rounded()))
    }

    var estimatedVirtualViewCount: Int {
        videoType == .panorama && reconstruct ? estimatedFrameCount * 12 : 0
    }

    var estimatedProcessDuration: String {
        guard estimatedFrameCount > 0 else { return "Selecciona un video" }
        let seconds: Double
        if !reconstruct {
            let megapixels = Double(videoWidth * videoHeight) / 1_000_000
            seconds = max(5, videoDuration * max(0.08, megapixels / 30))
        } else if videoType == .panorama {
            // Calibrated against the proven 239 × 12 view, 100-minute run.
            let referencePixels = 7680.0 * 3840.0
            let resolutionFactor = max(0.08, Double(videoWidth * videoHeight) / referencePixels)
            seconds = max(20, Double(estimatedVirtualViewCount) * 2.1 * resolutionFactor)
        } else {
            let referencePixels = 1280.0 * 720.0
            let resolutionFactor = max(0.45, sqrt(Double(videoWidth * videoHeight) / referencePixels))
            seconds = max(20, Double(estimatedFrameCount) * 1.8 * resolutionFactor)
        }
        return formatEstimatedDuration(seconds)
    }

    override init() {
        super.init()
        let arguments = ProcessInfo.processInfo.arguments
        if let videoFlag = arguments.firstIndex(of: "--video"), arguments.indices.contains(videoFlag + 1) {
            setVideo(URL(fileURLWithPath: arguments[videoFlag + 1]))
        }
        refreshBrushAvailability()
        Task { await checkDependencies() }
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona un video"
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { setVideo(url) }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona la carpeta para guardar resultados"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { outputURL = url }
    }

    func chooseBrush() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona Brush o Brush.app"
        panel.message = "Selecciona el ejecutable brush_app descargado desde el repositorio oficial."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let selected = panel.url,
           let executable = resolveBrushExecutable(selected) {
            registerBrushExecutable(executable)
            appendBrushLog("Brush localizado: \(executable.path)")
        }
    }

    func chooseBrushDataset() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona un dataset COLMAP preparado para Brush"
        panel.message = "La carpeta debe contener images y sparse/0."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard isBrushDataset(url) else {
                appendBrushLog("Dataset no válido: faltan images o los archivos binarios de sparse/0.")
                return
            }
            brushDatasetURL = url
            appendBrushLog("Dataset seleccionado: \(url.path)")
        }
    }

    func chooseSplatPreview() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona un snapshot PLY de Brush"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard url.pathExtension.lowercased() == "ply" else {
                appendBrushLog("Selecciona un archivo con extensión .ply.")
                return
            }
            latestSplatURL = url
            previewMilestoneLabel = "PLY seleccionado"
            if let count = plyVertexCount(url) { brushSplatCount = count }
            appendBrushLog("Vista previa cargada: \(url.path)")
        }
    }

    func openLatestSplatInBrush() {
        guard !isBrushRunning else { return }
        guard let brush = brushExecutableURL ?? findBrushExecutable() else {
            brushState = .unavailable
            appendBrushLog("Brush no está disponible para abrir el resultado.")
            return
        }
        guard let splat = latestSplatURL, FileManager.default.fileExists(atPath: splat.path) else {
            appendBrushLog("Todavía no hay un Gaussian Splat entrenado para abrir.")
            return
        }

        let task = Process()
        task.executableURL = brush
        task.arguments = [splat.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        task.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.brushViewerProcess = nil
                if finished.terminationStatus != 0 {
                    self?.appendBrushLog("El visor de Brush terminó con código \(finished.terminationStatus).")
                }
            }
        }
        do {
            try task.run()
            brushViewerProcess = task
            appendBrushLog("Abriendo en Brush: \(splat.lastPathComponent)")
        } catch {
            appendBrushLog("No fue posible abrir Brush: \(error.localizedDescription)")
        }
    }

    func startBrushTraining() {
        guard brushStepsAreValid else {
            appendBrushLog("El número de pasos debe estar entre 1.000 y 30.000.")
            return
        }
        guard let brush = brushExecutableURL ?? findBrushExecutable() else {
            brushState = .unavailable
            appendBrushLog("Localiza Brush antes de iniciar el entrenamiento.")
            return
        }
        guard let dataset = resolvedBrushDatasetURL else {
            appendBrushLog("Selecciona o crea primero un dataset compatible con Brush.")
            return
        }
        guard !isRunning && !isBrushRunning else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let output = dataset.deletingLastPathComponent()
            .appendingPathComponent("brush-training-\(formatter.string(from: Date()))", isDirectory: true)
        guard let python = pythonPath() else {
            appendBrushLog("No se encontró Python para iniciar el adaptador de Brush.")
            return
        }
        let runner = pipelineDirectory().appendingPathComponent("brush_runner.py")
        guard FileManager.default.fileExists(atPath: runner.path) else {
            appendBrushLog("Falta brush_runner.py dentro del paquete de la aplicación.")
            return
        }

        brushExecutableURL = brush
        brushDatasetURL = dataset
        brushOutputURL = output
        latestSplatURL = nil
        previewPointCount = 0
        previewMilestoneLabel = ""
        shownPreviewMilestones.removeAll()
        brushStep = 0
        brushSplatCount = nil
        brushProgress = 0
        brushBufferedOutput = ""
        brushState = .running
        isBrushRunning = true
        appendBrushLog("\n— Entrenamiento Brush estándar —")
        appendBrushLog("Dataset: \(dataset.path)")
        appendBrushLog("\(brushTotalSteps.formatted()) pasos · máximo estándar de 10 millones de splats · snapshot cada 500 pasos")

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = [
            "-B",
            runner.path,
            "--brush", brush.path,
            "--dataset", dataset.path,
            "--output", output.path,
            "--total-steps", String(brushTotalSteps),
            "--export-every", String(brushExportEvery),
        ]
        task.currentDirectoryURL = pipelineDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = pipe
        brushProcess = task
        brushActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Entrenamiento Brush en curso"
        )

        let logURL = output.deletingLastPathComponent().appendingPathComponent("COLMAP360Studio-Brush-last.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        brushLogHandle = try? FileHandle(forWritingTo: logURL)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.brushLogHandle?.write(data)
                self?.consumeBrush(text)
            }
        }
        task.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                try? self.brushLogHandle?.close()
                self.brushLogHandle = nil
                self.brushMonitor?.invalidate()
                self.brushMonitor = nil
                self.isBrushRunning = false
                self.brushProcess = nil
                if let token = self.brushActivityToken {
                    ProcessInfo.processInfo.endActivity(token)
                    self.brushActivityToken = nil
                }
                if finished.terminationStatus == 0 {
                    self.brushProgress = 1
                    self.brushStep = self.brushTotalSteps
                    self.refreshLatestSplat(forceFinal: true)
                    self.brushState = .completed
                    self.appendBrushLog("✓ Entrenamiento Brush terminado.")
                    self.notifyCompletion()
                } else if finished.terminationStatus == 2 || finished.terminationStatus == 15 {
                    self.refreshLatestSplat()
                    self.brushState = .ready
                    self.appendBrushLog("Entrenamiento cancelado; los snapshots existentes se conservaron.")
                } else {
                    self.refreshLatestSplat()
                    self.brushState = .failed
                    self.appendBrushLog("Brush terminó con código \(finished.terminationStatus). Revisa el registro.")
                }
            }
        }
        do {
            try task.run()
            startBrushMonitor()
        } catch {
            isBrushRunning = false
            brushProcess = nil
            brushState = .failed
            if let token = brushActivityToken {
                ProcessInfo.processInfo.endActivity(token)
                brushActivityToken = nil
            }
            appendBrushLog("No fue posible iniciar Brush: \(error.localizedDescription)")
        }
    }

    func cancelBrushTraining() {
        brushProcess?.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if self?.brushProcess?.isRunning == true { self?.brushProcess?.terminate() }
        }
        appendBrushLog("Cancelación de Brush solicitada.")
    }

    func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = item as? URL }
            guard let url else { return }
            Task { @MainActor in self?.setVideo(url) }
        }
        return true
    }

    private func setVideo(_ url: URL) {
        guard ["mov", "mp4"].contains(url.pathExtension.lowercased()) else {
            appendLog("Selecciona un archivo .mov o .mp4.")
            return
        }
        videoURL = url
        lastOutputURL = nil
        videoDuration = 0
        videoWidth = 0
        videoHeight = 0
        inspectVideo(url)
    }

    private func inspectVideo(_ url: URL) {
        let ffprobe = toolPath("ffprobe") ?? "/opt/homebrew/bin/ffprobe"
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: ffprobe)
        task.arguments = ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height:format=duration", "-of", "default=noprint_wrappers=1", url.path]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run(); task.waitUntilExit()
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let values = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            })
            let width = Int(values["width"] ?? "") ?? 0
            let height = Int(values["height"] ?? "") ?? 0
            let duration = Double(values["duration"] ?? "") ?? 0
            videoWidth = width
            videoHeight = height
            videoDuration = duration
            videoSummary = "\(width) × \(height) · \(formatDuration(duration))" + (width == height * 2 ? " · panorama 2:1 detectado" : "")
            if width == height * 2 { videoType = .panorama }
        } catch {
            videoDuration = 0
            videoWidth = 0
            videoHeight = 0
            videoSummary = "No fue posible leer los datos del video."
        }
    }

    func start() {
        guard let videoURL else { return }
        guard dependencyState == .ready else {
            appendLog("Primero usa ‘Preparar Mac’ para revisar las dependencias.")
            return
        }
        let arguments = [
            "--video", videoURL.path, "--type", videoType.rawValue,
            "--fps", String(fps), "--output", outputURL.path,
            "--camera-model", cameraModel.rawValue,
        ] + (reconstruct ? [] : ["--frames-only"])
        progress = 0.01
        lastOutputURL = nil
        runPythonScript("process_video.py", arguments: arguments, action: "Procesando video")
    }

    func prepareMac() {
        let support = appSupportDirectory()
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        runExecutable("/bin/bash", arguments: [pipelineDirectory().appendingPathComponent("setup_macos.sh").path, "--venv", support.appendingPathComponent(".venv").path], action: "Preparando Python, FFmpeg y COLMAP", isSetup: true)
    }

    func cancel() {
        process?.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if self?.process?.isRunning == true { self?.process?.terminate() }
        }
        appendLog("Cancelación solicitada. Los archivos ya generados se conservarán.")
    }

    private func checkDependencies() async {
        dependencyState = .checking
        refreshBrushAvailability()
        let binariesReady = toolPath("ffmpeg") != nil && toolPath("ffprobe") != nil
        let pythonReady = pythonPath().map { path in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["-c", "import pycolmap, cv2, PIL, scipy, tqdm"]
            task.standardOutput = Pipe(); task.standardError = Pipe()
            do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 0 }
            catch { return false }
        } ?? false
        dependencyState = binariesReady && pythonReady && brushExecutableURL != nil ? .ready : .missing
    }

    private func runPythonScript(_ name: String, arguments: [String], action: String) {
        guard let python = pythonPath() else {
            appendLog("No se encontró el entorno Python. Usa ‘Preparar Mac’.")
            dependencyState = .missing
            return
        }
        runExecutable(python, arguments: ["-B", pipelineDirectory().appendingPathComponent(name).path] + arguments, action: action)
    }

    private func runExecutable(_ executable: String, arguments: [String], action: String, isSetup: Bool = false) {
        guard !isRunning else { return }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = pipelineDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = pipe
        process = task
        isRunning = true
        if !isSetup {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "Reconstrucción COLMAP en curso"
            )
        }
        statusText = action
        bufferedOutput = ""
        appendLog("\n— \(action) —")

        let destination = outputURL.appendingPathComponent("COLMAP360Studio-last.log")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: destination)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.logHandle?.write(data)
                self?.consume(text)
            }
        }
        task.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                try? self.logHandle?.close(); self.logHandle = nil
                self.isRunning = false
                self.process = nil
                if let token = self.activityToken {
                    ProcessInfo.processInfo.endActivity(token)
                    self.activityToken = nil
                }
                if finished.terminationStatus == 0 {
                    self.progress = 1
                    self.statusText = isSetup ? "Mac preparado" : "Proceso terminado"
                    if !isSetup {
                        self.completedConfiguration = self.currentConfiguration
                        self.discoverBrushDataset()
                        self.notifyCompletion()
                    }
                    self.appendLog(isSetup ? "✓ El Mac está listo." : "✓ Proceso completado correctamente.")
                    if isSetup {
                        self.refreshBrushAvailability()
                        Task { await self.checkDependencies() }
                    }
                } else {
                    self.statusText = "El proceso no terminó"
                    self.appendLog("Error: el proceso terminó con código \(finished.terminationStatus). Revisa las últimas líneas del registro.")
                    if isSetup { self.dependencyState = .missing }
                }
            }
        }
        do { try task.run() }
        catch {
            isRunning = false; process = nil
            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
                activityToken = nil
            }
            appendLog("No fue posible iniciar: \(error.localizedDescription)")
        }
    }

    private func consume(_ text: String) {
        bufferedOutput += text
        let lines = bufferedOutput.components(separatedBy: .newlines)
        bufferedOutput = lines.last ?? ""
        for line in lines.dropLast() {
            if line.hasPrefix("::brush-path ") {
                let path = String(line.dropFirst("::brush-path ".count))
                if let executable = resolveBrushExecutable(URL(fileURLWithPath: path)) {
                    registerBrushExecutable(executable)
                    appendBrushLog("Brush instalado y registrado: \(executable.path)")
                }
                continue
            }
            if line.hasPrefix("::progress ") {
                let parts = line.split(separator: " ", maxSplits: 2)
                if parts.count >= 2, let value = Double(parts[1]) { progress = value }
                if parts.count == 3 { statusText = String(parts[2]) }
            } else if line.hasPrefix("::output ") {
                let path = String(line.dropFirst("::output ".count))
                lastOutputURL = URL(fileURLWithPath: path)
                appendLog("Resultado: \(path)")
            } else if !line.isEmpty {
                appendLog(line)
            }
        }
    }

    private func consumeBrush(_ text: String) {
        brushBufferedOutput += text
        let lines = brushBufferedOutput.components(separatedBy: .newlines)
        brushBufferedOutput = lines.last ?? ""
        for line in lines.dropLast() where !line.isEmpty {
            if line.hasPrefix("::brush-output ") {
                brushOutputURL = URL(fileURLWithPath: String(line.dropFirst("::brush-output ".count)))
                continue
            }
            updateBrushMetrics(from: line)
            appendBrushLog(line)
        }
    }

    private func updateBrushMetrics(from line: String) {
        let stepPatterns = [
            #"(?i)(?:step|iteration|iter)\s*[:#]?\s*(\d+)(?:\s*/\s*(\d+))?"#,
            #"(?i)training\s+(\d+)\s*/\s*(\d+)"#,
        ]
        for pattern in stepPatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let stepRange = Range(match.range(at: 1), in: line),
                  let step = Int(line[stepRange]) else { continue }
            brushStep = min(step, brushTotalSteps)
            brushProgress = min(1, Double(brushStep) / Double(brushTotalSteps))
            break
        }
        if let expression = try? NSRegularExpression(pattern: #"(?i)([0-9][0-9,._]*)\s+splats?"#),
           let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            let digits = line[range].filter(\.isNumber)
            brushSplatCount = Int(digits)
        }
    }

    private func appendBrushLog(_ line: String) {
        brushLogText += (brushLogText.isEmpty ? "" : "\n") + line
    }

    private func startBrushMonitor() {
        brushMonitor?.invalidate()
        brushMonitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLatestSplat() }
        }
        refreshLatestSplat()
    }

    private func refreshLatestSplat(forceFinal: Bool = false) {
        guard let output = brushOutputURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: output,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let candidates = contents
            .filter { $0.pathExtension.lowercased() == "ply" }
            .compactMap { url -> (url: URL, step: Int)? in
                guard let step = splatStep(url) else { return nil }
                return (url, step)
            }
            .sorted { $0.step < $1.step }
        guard let first = candidates.first, let latest = candidates.last else { return }

        brushStep = min(latest.step, brushTotalSteps)
        brushProgress = min(1, Double(brushStep) / Double(brushTotalSteps))
        if let count = plyVertexCount(latest.url) { brushSplatCount = count }

        var preview: (url: URL, step: Int, milestone: Int, label: String)?
        if !shownPreviewMilestones.contains(100), (latest.step >= brushTotalSteps || forceFinal) {
            preview = (latest.url, latest.step, 100, "Entrenamiento terminado")
        } else if !shownPreviewMilestones.contains(0) {
            preview = (first.url, first.step, 0, "Vista inicial")
        } else if !shownPreviewMilestones.contains(50), latest.step >= brushTotalSteps / 2 {
            let midpoint = candidates.first(where: { $0.step >= brushTotalSteps / 2 }) ?? latest
            preview = (midpoint.url, midpoint.step, 50, "50% del entrenamiento")
        }

        if let preview {
            shownPreviewMilestones.insert(preview.milestone)
            latestSplatURL = preview.url
            previewMilestoneLabel = preview.label
            if let count = plyVertexCount(preview.url) { previewPointCount = count }
            appendBrushLog("Visor SuperSplat actualizado (\(preview.label)): \(preview.url.lastPathComponent)")
        }
    }

    private func splatStep(_ url: URL) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)(?=\.ply$)"#),
              let match = expression.firstMatch(
                in: url.lastPathComponent,
                range: NSRange(url.lastPathComponent.startIndex..., in: url.lastPathComponent)
              ),
              let range = Range(match.range(at: 1), in: url.lastPathComponent) else { return nil }
        return Int(url.lastPathComponent[range])
    }

    private func plyVertexCount(_ url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_384),
              let marker = "end_header\n".data(using: .utf8),
              let end = data.range(of: marker)?.upperBound,
              let header = String(data: data[..<end], encoding: .utf8) else { return nil }
        for line in header.components(separatedBy: .newlines) where line.hasPrefix("element vertex ") {
            return Int(line.split(separator: " ").last ?? "")
        }
        return nil
    }

    private func discoverBrushDataset() {
        guard let dataset = resolvedBrushDatasetURL else { return }
        brushDatasetURL = dataset
        appendBrushLog("Dataset COLMAP listo para Brush: \(dataset.path)")
    }

    private func refreshBrushAvailability() {
        brushExecutableURL = findBrushExecutable()
        if let brushExecutableURL {
            UserDefaults.standard.set(brushExecutableURL.path, forKey: Self.brushExecutablePathKey)
        }
        brushState = brushExecutableURL == nil ? .unavailable : .ready
    }

    private func registerBrushExecutable(_ executable: URL) {
        UserDefaults.standard.set(executable.path, forKey: Self.brushExecutablePathKey)
        brushExecutableURL = executable
        brushState = .ready
    }

    private func findBrushExecutable() -> URL? {
        var candidates: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["BRUSH_PATH"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured))
        }
        if let saved = UserDefaults.standard.string(forKey: Self.brushExecutablePathKey), !saved.isEmpty {
            candidates.append(URL(fileURLWithPath: saved))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let productRoot = pipelineDirectory().deletingLastPathComponent().deletingLastPathComponent()
        candidates += [
            URL(fileURLWithPath: "/Applications/Brush.app"),
            URL(fileURLWithPath: "/Applications/brush-app.app"),
            home.appendingPathComponent("Applications/Brush.app"),
            home.appendingPathComponent("Applications/brush-app.app"),
            appSupportDirectory().appendingPathComponent("Brush/brush_app"),
            home.appendingPathComponent("Downloads/brush-app-aarch64-apple-darwin/brush_app"),
            productRoot.appendingPathComponent("Brush/brush-app-aarch64-apple-darwin/brush_app"),
            URL(fileURLWithPath: "/opt/homebrew/bin/brush_app"),
            URL(fileURLWithPath: "/usr/local/bin/brush_app"),
        ]
        return candidates.lazy.compactMap(resolveBrushExecutable).first
    }

    private func resolveBrushExecutable(_ candidate: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else { return nil }
        if candidate.pathExtension.lowercased() == "app" || isDirectory.boolValue {
            if let executable = Bundle(url: candidate)?.executableURL,
               FileManager.default.isExecutableFile(atPath: executable.path) { return executable }
            for name in ["brush_app", "brush-app", "brush"] {
                let executable = candidate.appendingPathComponent("Contents/MacOS/\(name)")
                if FileManager.default.isExecutableFile(atPath: executable.path) { return executable }
            }
            return nil
        }
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private func isBrushDataset(_ url: URL) -> Bool {
        let manager = FileManager.default
        let images = url.appendingPathComponent("images")
        guard manager.fileExists(atPath: images.path) else { return false }
        let sparseCandidates = [url.appendingPathComponent("sparse/0"), url.appendingPathComponent("sparse")]
        return sparseCandidates.contains { sparse in
            ["cameras.bin", "images.bin", "points3D.bin"].allSatisfy {
                manager.fileExists(atPath: sparse.appendingPathComponent($0).path)
            }
        }
    }

    private func appendLog(_ line: String) {
        logText += (logText.isEmpty ? "" : "\n") + line
    }

    private func notifyCompletion() {
        NSSound(named: NSSound.Name("Glass"))?.play()
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func pipelineDirectory() -> URL {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("Pipeline"),
           FileManager.default.fileExists(atPath: resource.appendingPathComponent("process_video.py").path) { return resource }
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("process_video.py").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func appSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3GOVideo/COLMAP360Studio", isDirectory: true)
    }

    private func pythonPath() -> String? {
        let candidates = [
            appSupportDirectory().appendingPathComponent(".venv/bin/python").path,
            pipelineDirectory().appendingPathComponent(".venv/bin/python").path,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".venv/bin/python").path,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func toolPath(_ name: String) -> String? {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func formatDuration(_ value: Double) -> String {
        let seconds = Int(value.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func formatEstimatedDuration(_ value: Double) -> String {
        let minutes = max(1, Int((value / 60).rounded()))
        if minutes < 2 { return "≈ menos de 2 min" }
        if minutes < 60 { return "≈ \(minutes) min" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "≈ \(hours) h" : "≈ \(hours) h \(remainingMinutes) min"
    }
}
