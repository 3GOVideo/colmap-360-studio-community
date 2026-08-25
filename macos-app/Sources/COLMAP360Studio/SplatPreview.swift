import AppKit
import SwiftUI
import WebKit

struct SplatPreview: NSViewRepresentable {
    let fileURL: URL?
    @Binding var displayedPointCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(resourceDirectory: Self.resourceDirectory())
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "colmap360")
        configuration.preferences.isElementFullscreenEnabled = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        context.coordinator.webView = view
        Self.showPlaceholder(in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != fileURL else { return }
        context.coordinator.loadedURL = fileURL
        context.coordinator.schemeHandler.modelURL = fileURL

        guard let fileURL else {
            displayedPointCount = 0
            Self.showPlaceholder(in: view)
            return
        }

        displayedPointCount = Self.vertexCount(in: fileURL) ?? 0
        guard context.coordinator.schemeHandler.resourcesAreAvailable else {
            Self.showError("No se encontraron los recursos locales de SuperSplat.", in: view)
            return
        }

        var components = URLComponents(string: "colmap360://viewer/index.html")!
        components.queryItems = [
            URLQueryItem(name: "content", value: "colmap360://viewer/model/current.ply?revision=\(UUID().uuidString)"),
            URLQueryItem(name: "settings", value: "colmap360://viewer/settings.json"),
            URLQueryItem(name: "webgl", value: ""),
            URLQueryItem(name: "noui", value: ""),
            URLQueryItem(name: "noanim", value: ""),
            URLQueryItem(name: "nofx", value: ""),
            URLQueryItem(name: "lang", value: "es"),
        ]
        if let url = components.url {
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        fileprivate let schemeHandler: SuperSplatSchemeHandler
        weak var webView: WKWebView?
        var loadedURL: URL?

        fileprivate init(resourceDirectory: URL?) {
            schemeHandler = SuperSplatSchemeHandler(resourceDirectory: resourceDirectory)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            SplatPreview.showError(error.localizedDescription, in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            SplatPreview.showError(error.localizedDescription, in: webView)
        }
    }

    private static func resourceDirectory() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SuperSplat", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.js").path) {
            return bundled
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("supersplat-viewer/node_modules/@playcanvas/supersplat-viewer/public", isDirectory: true)
        return FileManager.default.fileExists(atPath: local.appendingPathComponent("index.js").path) ? local : nil
    }

    private static func vertexCount(in url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536),
              let marker = "end_header\n".data(using: .utf8),
              let end = data.range(of: marker)?.upperBound,
              let header = String(data: data[..<end], encoding: .utf8) else { return nil }
        for line in header.components(separatedBy: .newlines) where line.hasPrefix("element vertex ") {
            return Int(line.split(separator: " ").last ?? "")
        }
        return nil
    }

    private static func showPlaceholder(in view: WKWebView) {
        view.loadHTMLString(
            """
            <!doctype html><html><body style="margin:0;background:#0b0b0d"></body></html>
            """,
            baseURL: nil
        )
    }

    fileprivate static func showError(_ message: String, in view: WKWebView) {
        let safe = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        view.loadHTMLString(
            """
            <!doctype html><html><body style="margin:0;background:#0b0b0d;color:#ff9f43;font:13px -apple-system;display:flex;align-items:center;justify-content:center;height:100vh;text-align:center;padding:24px;box-sizing:border-box">\(safe)</body></html>
            """,
            baseURL: nil
        )
    }
}

fileprivate final class SuperSplatSchemeHandler: NSObject, WKURLSchemeHandler {
    let resourceDirectory: URL?
    var modelURL: URL?

    private let lock = NSLock()
    private var stoppedTasks = Set<ObjectIdentifier>()

    var resourcesAreAvailable: Bool { resourceDirectory != nil }

    init(resourceDirectory: URL?) {
        self.resourceDirectory = resourceDirectory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        stoppedTasks.remove(identifier)
        lock.unlock()

        guard let requestURL = urlSchemeTask.request.url,
              let source = sourceURL(for: requestURL) else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "COLMAP360SuperSplat",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Recurso SuperSplat no encontrado"]
            ))
            return
        }

        let mimeType = Self.mimeType(for: source)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let values = try source.resourceValues(forKeys: [.fileSizeKey])
                let response = URLResponse(
                    url: requestURL,
                    mimeType: mimeType,
                    expectedContentLength: values.fileSize ?? -1,
                    textEncodingName: mimeType.hasPrefix("text/") || mimeType.contains("javascript") || mimeType.contains("json") ? "utf-8" : nil
                )
                guard !self.isStopped(identifier) else { return }
                urlSchemeTask.didReceive(response)

                let handle = try FileHandle(forReadingFrom: source)
                defer { try? handle.close() }
                while !self.isStopped(identifier), let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                    urlSchemeTask.didReceive(chunk)
                }
                guard !self.isStopped(identifier) else { return }
                urlSchemeTask.didFinish()
            } catch {
                guard !self.isStopped(identifier) else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        stoppedTasks.insert(identifier)
        lock.unlock()
    }

    private func isStopped(_ identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedTasks.contains(identifier)
    }

    private func sourceURL(for requestURL: URL) -> URL? {
        switch requestURL.path {
        case "/model/current.ply":
            return modelURL
        case "/index.html":
            return resourceDirectory?.appendingPathComponent("index.html")
        case "/index.css":
            return resourceDirectory?.appendingPathComponent("index.css")
        case "/index.js":
            return resourceDirectory?.appendingPathComponent("index.js")
        case "/settings.json":
            return resourceDirectory?.appendingPathComponent("settings.json")
        default:
            return nil
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "text/javascript"
        case "json": return "application/json"
        case "ply": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }
}
