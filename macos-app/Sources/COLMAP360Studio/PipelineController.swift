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

private struct JobConfiguration: Equatable {
    let videoPath: String
    let outputPath: String
    let videoType: VideoType
    let fps: Int
    let reconstruct: Bool
}

@MainActor
final class PipelineController: NSObject, ObservableObject {
    @Published var videoURL: URL?
    @Published var outputURL: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
    @Published var videoType: VideoType = .panorama
    @Published var fps = 2
    @Published var reconstruct = true
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

    private var process: Process?
    private var logHandle: FileHandle?
    private var bufferedOutput = ""
    private var activityToken: NSObjectProtocol?
    private var completedConfiguration: JobConfiguration?

    private var currentConfiguration: JobConfiguration? {
        guard let videoURL else { return nil }
        return JobConfiguration(
            videoPath: videoURL.path,
            outputPath: outputURL.path,
            videoType: videoType,
            fps: fps,
            reconstruct: reconstruct
        )
    }

    var hasCompletedCurrentConfiguration: Bool {
        currentConfiguration != nil && currentConfiguration == completedConfiguration
    }

    var canStart: Bool {
        currentConfiguration != nil && !isRunning && !hasCompletedCurrentConfiguration
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
        let binariesReady = toolPath("ffmpeg") != nil && toolPath("ffprobe") != nil
        let pythonReady = pythonPath().map { path in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["-c", "import pycolmap, cv2, PIL, scipy, tqdm"]
            task.standardOutput = Pipe(); task.standardError = Pipe()
            do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 0 }
            catch { return false }
        } ?? false
        dependencyState = binariesReady && pythonReady ? .ready : .missing
    }

    private func runPythonScript(_ name: String, arguments: [String], action: String) {
        guard let python = pythonPath() else {
            appendLog("No se encontró el entorno Python. Usa ‘Preparar Mac’.")
            dependencyState = .missing
            return
        }
        runExecutable(python, arguments: [pipelineDirectory().appendingPathComponent(name).path] + arguments, action: action)
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
                        self.notifyCompletion()
                    }
                    self.appendLog(isSetup ? "✓ El Mac está listo." : "✓ Proceso completado correctamente.")
                    if isSetup { Task { await self.checkDependencies() } }
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
