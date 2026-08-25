import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var pipeline: PipelineController
    @State private var isDropTargeted = false
    @State private var showSetupConfirmation = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                TabView(selection: $selectedTab) {
                    datasetWorkspace
                        .tabItem { Label("Dataset COLMAP", systemImage: "camera.metering.matrix") }
                        .tag(0)
                    brushWorkspace
                        .tabItem { Label("Brush Studio", systemImage: "view.3d") }
                        .tag(1)
                }
            }
        }
        .alert("Preparar este Mac", isPresented: $showSetupConfirmation) {
            Button("Cancelar", role: .cancel) { }
            Button("Revisar e instalar") { pipeline.prepareMac() }
        } message: {
            Text("La app revisará Python, FFmpeg y COLMAP. Si falta algo, Homebrew y Python podrán descargarlo. El avance aparecerá en el registro.")
        }
        .tint(.blue)
    }

    private var datasetWorkspace: some View {
        VStack(spacing: 10) {
            videoCard
            optionsCard
            outputCard
            runCard
            logCard
        }
        .padding(16)
    }

    private var brushWorkspace: some View {
        HStack(spacing: 12) {
            VStack(spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(pipeline.brushState.label, systemImage: pipeline.brushState.icon)
                            .font(.headline)
                            .foregroundStyle(pipeline.brushState.color)
                        pathSummary(
                            title: "Motor Brush",
                            path: pipeline.brushExecutableURL?.path ?? "No localizado"
                        )
                        Button("Localizar Brush…") { pipeline.chooseBrush() }
                            .disabled(pipeline.isBrushRunning || pipeline.isRunning)
                        Link(
                            "Descargar Brush oficial ↗",
                            destination: URL(string: "https://github.com/ArthurBrussee/brush/releases/latest")!
                        )
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("1. Motor", systemImage: "cpu")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        pathSummary(
                            title: "Dataset",
                            path: pipeline.resolvedBrushDatasetURL?.path ?? "Crea o selecciona un dataset"
                        )
                        Button("Seleccionar dataset…") { pipeline.chooseBrushDataset() }
                            .disabled(pipeline.isBrushRunning || pipeline.isRunning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("2. Datos", systemImage: "externaldrive")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            metricValue(pipeline.brushStep.formatted(), label: "Paso")
                            metricValue(pipeline.brushSplatCount?.formatted() ?? "—", label: "Splats")
                        }
                        ProgressView(value: pipeline.brushProgress) {
                            Text("\(pipeline.brushStep.formatted()) / \(pipeline.brushTotalSteps.formatted())")
                                .font(.caption.monospacedDigit())
                        }
                        Text("Configuración estándar de Brush 0.3: 30.000 pasos y máximo de 10 millones de splats. El visor recibe un snapshot cada 500 pasos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            if pipeline.isBrushRunning {
                                Button("Cancelar", role: .destructive) { pipeline.cancelBrushTraining() }
                            }
                            Spacer()
                            Button {
                                pipeline.startBrushTraining()
                            } label: {
                                Label("Entrenar en Brush", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!pipeline.canStartBrush)
                        }
                        if let output = pipeline.brushOutputURL {
                            Button("Mostrar exports") {
                                NSWorkspace.shared.activateFileViewerSelecting([output])
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(6)
                } label: {
                    Label("3. Entrenamiento", systemImage: "sparkles")
                }
                Spacer(minLength: 0)
            }
            .frame(width: 330)

            VStack(spacing: 10) {
                GroupBox {
                    ZStack(alignment: .topLeading) {
                        SplatPreview(
                            fileURL: pipeline.latestSplatURL,
                            displayedPointCount: $pipeline.previewPointCount
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        if pipeline.latestSplatURL == nil {
                            VStack(spacing: 10) {
                                Image(systemName: "view.3d")
                                    .font(.system(size: 38))
                                    .foregroundStyle(.secondary)
                                Text("Esperando el primer snapshot")
                                    .font(.headline)
                                Text("El Gaussian Splat aparecerá aquí mientras Brush entrena.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Vista previa ligera de los centros de splats; el render final conserva toda la información en el PLY.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            HStack(spacing: 8) {
                                Label(pipeline.latestSplatURL?.lastPathComponent ?? "", systemImage: "cube.transparent")
                                Text("·")
                                Text("\(pipeline.previewPointCount.formatted()) puntos")
                            }
                            .font(.caption.monospacedDigit())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                        }
                    }
                } label: {
                    HStack {
                        Label("Visor integrado", systemImage: "rotate.3d")
                        Spacer()
                        Text("Arrastra para orbitar · rueda para acercar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)

                GroupBox {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(pipeline.brushLogText.isEmpty ? "Aquí verás la carga del dataset, los pasos de entrenamiento y cada exportación." : pipeline.brushLogText)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(pipeline.brushLogText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .id("brushLogBottom")
                        }
                        .onChange(of: pipeline.brushLogText) { _ in
                            proxy.scrollTo("brushLogBottom", anchor: .bottom)
                        }
                    }
                    .frame(height: 130)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } label: {
                    HStack {
                        Label("Registro Brush", systemImage: "terminal")
                        Spacer()
                        Button("Limpiar") { pipeline.brushLogText = "" }
                            .buttonStyle(.plain)
                            .disabled(pipeline.isBrushRunning)
                    }
                }
            }
        }
        .padding(16)
    }

    private func pathSummary(title: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(path).font(.caption).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private func metricValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(width: 48, height: 48)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "view.3d")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("COLMAP 360 Studio")
                    .font(.title2.weight(.bold))
                Text("De video a dataset para Gaussian Splat")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(pipeline.dependencyState.label, systemImage: pipeline.dependencyState.icon)
                .foregroundStyle(pipeline.dependencyState.color)
                .font(.callout.weight(.medium))
            Button { showSetupConfirmation = true } label: {
                Label("Preparar Mac", systemImage: "gearshape.fill")
            }
                .buttonStyle(.bordered)
                .disabled(pipeline.isRunning)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var videoCard: some View {
        GroupBox {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                    Image(systemName: pipeline.videoURL == nil ? "film.stack" : "play.rectangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(pipeline.videoURL == nil ? Color.secondary : Color.blue)
                }
                .frame(width: 72, height: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pipeline.videoURL?.lastPathComponent ?? "Selecciona o arrastra un video")
                        .font(.headline)
                        .lineLimit(1)
                    Text(pipeline.videoSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Seleccionar video…") { pipeline.chooseVideo() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pipeline.isRunning)
            }
            .padding(6)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                pipeline.receiveDrop(providers)
            }
        } label: {
            Label("1. Video de entrada", systemImage: "video")
        }
    }

    private var optionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tipo de video")
                        .frame(width: 160, alignment: .leading)
                    Picker("Tipo de video", selection: $pipeline.videoType) {
                        Label("360° equirectangular", systemImage: "globe.americas").tag(VideoType.panorama)
                        Label("Plano / convencional", systemImage: "rectangle").tag(VideoType.flat)
                    }
                    .pickerStyle(.segmented)
                    .disabled(pipeline.isRunning)
                }
                HStack {
                    Text("Fotogramas por segundo")
                        .frame(width: 160, alignment: .leading)
                    Picker("FPS", selection: $pipeline.fps) {
                        ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) FPS").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(pipeline.isRunning)
                }
                estimationSummary
                Toggle(isOn: $pipeline.reconstruct) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reconstruir con COLMAP y preparar para Brush")
                        Text(pipeline.videoType.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(pipeline.isRunning)
            }
            .padding(8)
        } label: {
            Label("2. Procesamiento", systemImage: "slider.horizontal.3")
        }
    }

    private var estimationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label("Resumen estimado", systemImage: "speedometer")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 160, alignment: .leading)
                if pipeline.estimatedFrameCount > 0 {
                    estimateValue(
                        pipeline.estimatedFrameCount.formatted(),
                        label: "Fotogramas"
                    )
                    Divider().frame(height: 34)
                    if pipeline.videoType == .panorama && pipeline.reconstruct {
                        estimateValue(
                            pipeline.estimatedVirtualViewCount.formatted(),
                            label: "Vistas virtuales 360°"
                        )
                        Divider().frame(height: 34)
                    }
                    estimateValue(
                        pipeline.estimatedProcessDuration,
                        label: "Duración promedio"
                    )
                } else {
                    Text("Selecciona un video para calcular fotogramas y duración.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Text("Cálculo orientativo según duración, resolución, FPS y pruebas anteriores; la escena y el rendimiento del Mac pueden cambiar el tiempo real.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 174)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.blue.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.blue.opacity(0.18)))
        )
    }

    private func estimateValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outputCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pipeline.outputURL.path)
                        .lineLimit(1).truncationMode(.middle)
                    Text("La app crea una carpeta nueva y nunca sobrescribe resultados anteriores.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cambiar…") { pipeline.chooseOutput() }
                    .disabled(pipeline.isRunning)
            }
            .padding(6)
        } label: {
            Label("3. Carpeta de resultados", systemImage: "folder")
        }
    }

    private var runCard: some View {
        VStack(spacing: 12) {
            if pipeline.isRunning || pipeline.progress > 0 {
                ProgressView(value: pipeline.progress) {
                    Text(pipeline.statusText).font(.callout.weight(.medium))
                }
            }
            HStack {
                if pipeline.isRunning {
                    Button("Cancelar", role: .destructive) { pipeline.cancel() }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if let folder = pipeline.lastOutputURL, !pipeline.isRunning {
                    Button("Mostrar resultado") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        .buttonStyle(.bordered)
                }
                Button {
                    pipeline.start()
                } label: {
                    Label(
                        pipeline.hasCompletedCurrentConfiguration
                            ? (pipeline.reconstruct ? "Dataset creado" : "Fotogramas creados")
                            : (pipeline.reconstruct ? "Crear dataset para Brush" : "Extraer fotogramas"),
                        systemImage: pipeline.hasCompletedCurrentConfiguration ? "checkmark.circle.fill" : "sparkles"
                    )
                        .frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!pipeline.canStart)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.08)))
    }

    private var logCard: some View {
        GroupBox {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(pipeline.logText.isEmpty ? "Aquí verás cada etapa y la ubicación de las carpetas generadas." : pipeline.logText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(pipeline.logText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("logBottom")
                }
                .frame(minHeight: 80, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: pipeline.logText) { _ in proxy.scrollTo("logBottom", anchor: .bottom) }
            }
        } label: {
            HStack {
                Label("Registro", systemImage: "text.alignleft")
                Spacer()
                Button("Limpiar") { pipeline.logText = "" }
                    .buttonStyle(.plain).disabled(pipeline.isRunning)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
