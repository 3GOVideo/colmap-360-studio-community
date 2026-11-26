import AVKit
import SwiftUI

struct VideoTrimEditor: View {
    let duration: Double
    let fps: Int
    let isPanorama: Bool
    let onApply: (ClosedRange<Double>?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var startText: String
    @State private var endText: String

    init(
        url: URL, duration: Double, fps: Int, initialRange: ClosedRange<Double>?,
        isPanorama: Bool, onApply: @escaping (ClosedRange<Double>?) -> Void
    ) {
        self.duration = duration
        self.fps = fps
        self.isPanorama = isPanorama
        self.onApply = onApply
        _player = State(initialValue: AVPlayer(url: url))
        _startText = State(initialValue: String(initialRange?.lowerBound ?? 0))
        _endText = State(initialValue: String(initialRange?.upperBound ?? duration))
    }

    private var start: Double? { seconds(from: startText) }
    private var end: Double? { seconds(from: endText) }
    private var minimumLength: Double { 1 / Double(fps) }
    private var isFullVideo: Bool { start == 0 && end == duration }

    private var errorText: String? {
        guard let start, let end, start >= 0, end <= duration, start < end else {
            return "El inicio debe quedar antes del fin y ambos dentro del video."
        }
        if !isFullVideo && end - start + 1e-9 < minimumLength {
            return "El tramo es demasiado corto para extraer un fotograma a \(fps) FPS."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recortar video").font(.title2.bold())
            if isPanorama {
                Text("Vista previa del panorama equirectangular completo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TrimPlayerView(player: player)
                .frame(height: 300)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            timeline
            HStack(spacing: 16) {
                timeField("Inicio (s)", text: $startText)
                timeField("Fin (s)", text: $endText)
                Spacer()
                if let start, let end, errorText == nil {
                    Text("Duración del tramo: \(Self.timecode(end - start))")
                        .font(.callout.monospacedDigit())
                }
            }
            Text(errorText ?? "Introduce los tiempos en segundos o arrastra los tiradores.")
                .font(.caption)
                .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
            HStack {
                Button("Restablecer") {
                    startText = "0"
                    endText = String(duration)
                    preview(at: 0)
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Aplicar") {
                    guard let start, let end, errorText == nil else { return }
                    onApply(isFullVideo ? nil : start...end)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(errorText != nil)
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear { preview(at: start ?? 0) }
        .onDisappear { player.pause() }
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 14
            let trackWidth = max(1, geometry.size.width - 2 * inset)
            let left = inset + trackWidth * (min(max(start ?? 0, 0), duration) / duration)
            let right = inset + trackWidth * (min(max(end ?? duration, 0), duration) / duration)
            ZStack(alignment: .topLeading) {
                Capsule().fill(.quaternary)
                    .frame(width: trackWidth, height: 6)
                    .offset(x: inset, y: 15)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(0, right - left), height: 6)
                    .offset(x: left, y: 15)
                handle("Inicio", icon: "chevron.right", x: left) { position in
                    let upper = max(0, min(end ?? duration, duration) - minimumLength)
                    updateTime(min(seconds(at: position, inset: inset, width: trackWidth), upper), isStart: true)
                }
                handle("Fin", icon: "chevron.left", x: right) { position in
                    let lower = min(duration, max(0, start ?? 0) + minimumLength)
                    updateTime(max(seconds(at: position, inset: inset, width: trackWidth), lower), isStart: false)
                }
            }
            .coordinateSpace(name: "trimTimeline")
        }
        .frame(height: 36)
        .accessibilityHidden(true) // The labeled time fields provide keyboard and VoiceOver access.
    }

    private func handle(_ title: String, icon: String, x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor)
            .overlay {
                Image(systemName: icon).font(.caption2.bold()).foregroundStyle(.white)
            }
            .frame(width: 18, height: 28)
            .frame(width: 28, height: 36)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimTimeline"))
                .onChanged { onDrag($0.location.x) })
            .position(x: x, y: 18)
            .help(title)
    }

    private func timeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(title, text: text)
                .monospacedDigit()
                .onChange(of: text.wrappedValue) { value in
                    if let time = seconds(from: value) { preview(at: time) }
                }
        }
        .frame(width: 140)
    }

    private func seconds(at x: CGFloat, inset: CGFloat, width: CGFloat) -> Double {
        min(max(Double((x - inset) / width), 0), 1) * duration
    }

    private func seconds(from text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              value.isFinite else { return nil }
        return value
    }

    private func updateTime(_ value: Double, isStart: Bool) {
        let rounded = (value * 1_000).rounded(isStart ? .down : .up) / 1_000
        if isStart {
            startText = String(max(0, rounded))
        } else {
            endText = String(min(duration, rounded))
        }
    }

    private func preview(at seconds: Double) {
        guard (0...duration).contains(seconds) else { return }
        player.pause()
        let nearEnd = max(0, duration - 1.0 / 120)
        player.seek(to: CMTime(seconds: min(seconds, nearEnd), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    static func timecode(_ interval: Double) -> String {
        let ms = Int((interval * 1_000).rounded())
        let seconds = ms / 1_000
        return String(format: "%02d:%02d.%03d", seconds / 60, seconds % 60, ms % 1_000)
    }
}

// Bridge directly to AppKit to avoid the AVKit SwiftUI player bridge on macOS 14.5.
private struct TrimPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
