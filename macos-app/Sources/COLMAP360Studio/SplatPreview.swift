import AppKit
import SceneKit
import SwiftUI
import simd

struct SplatPreview: NSViewRepresentable {
    let fileURL: URL?
    @Binding var displayedPointCount: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = Self.emptyScene()
        view.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.loadedURL != fileURL else { return }
        context.coordinator.loadedURL = fileURL
        context.coordinator.loadTask?.cancel()
        guard let fileURL else {
            displayedPointCount = 0
            view.scene = Self.emptyScene()
            return
        }
        let coordinator = context.coordinator
        coordinator.loadTask = Task.detached(priority: .userInitiated) {
            do {
                let cloud = try PLYPointCloud.load(from: fileURL, maximumPoints: 300_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard coordinator.loadedURL == fileURL else { return }
                    displayedPointCount = cloud.sourcePointCount
                    view.scene = Self.scene(for: cloud)
                }
            } catch {
                await MainActor.run {
                    guard coordinator.loadedURL == fileURL else { return }
                    displayedPointCount = 0
                    view.scene = Self.errorScene(error.localizedDescription)
                }
            }
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        var loadTask: Task<Void, Never>?
    }

    private static func emptyScene() -> SCNScene {
        let scene = SCNScene()
        scene.rootNode.addChildNode(cameraNode(position: SCNVector3(0, 0, 4)))
        let grid = SCNFloor()
        grid.reflectivity = 0
        grid.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.13, alpha: 1)
        grid.firstMaterial?.emission.contents = NSColor(calibratedWhite: 0.08, alpha: 1)
        let gridNode = SCNNode(geometry: grid)
        gridNode.position.y = -1
        scene.rootNode.addChildNode(gridNode)
        return scene
    }

    private static func errorScene(_ message: String) -> SCNScene {
        let scene = emptyScene()
        let text = SCNText(string: "No se pudo leer el PLY\n\(message)", extrusionDepth: 0)
        text.font = NSFont.systemFont(ofSize: 0.18, weight: .medium)
        text.firstMaterial?.diffuse.contents = NSColor.systemOrange
        let node = SCNNode(geometry: text)
        node.position = SCNVector3(-1.4, 0, 0)
        scene.rootNode.addChildNode(node)
        return scene
    }

    private static func scene(for cloud: PLYPointCloud) -> SCNScene {
        let scene = SCNScene()
        let positions = cloud.positions
        let colors = cloud.colors
        let positionData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let positionSource = SCNGeometrySource(
            data: positionData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let indices = Array(0..<UInt32(positions.count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 2.2
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 5.0
        let geometry = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.isDoubleSided = true
        geometry.firstMaterial?.readsFromDepthBuffer = true
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let radius = max(0.5, cloud.radius)
        let camera = cameraNode(
            position: SCNVector3(
                cloud.center.x,
                cloud.center.y + radius * 0.15,
                cloud.center.z + radius * 2.6
            )
        )
        camera.look(at: SCNVector3(cloud.center.x, cloud.center.y, cloud.center.z))
        scene.rootNode.addChildNode(camera)
        return scene
    }

    private static func cameraNode(position: SCNVector3) -> SCNNode {
        let node = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.001
        camera.zFar = 100_000
        node.camera = camera
        node.position = position
        return node
    }
}

private struct PLYPointCloud {
    let positions: [SIMD3<Float>]
    let colors: [SIMD4<Float>]
    let sourcePointCount: Int
    let center: SIMD3<Float>
    let radius: Float

    private struct Property {
        let name: String
        let type: String
        let offset: Int
        let size: Int
    }

    static func load(from url: URL, maximumPoints: Int) throws -> PLYPointCloud {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let newlineMarker = "end_header\n".data(using: .utf8),
              let headerRange = data.range(of: newlineMarker) else {
            throw NSError(domain: "SplatPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cabecera PLY no válida"])
        }
        let headerEnd = headerRange.upperBound
        guard let header = String(data: data[..<headerEnd], encoding: .utf8) else {
            throw NSError(domain: "SplatPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cabecera PLY ilegible"])
        }
        let lines = header.split(whereSeparator: \Character.isNewline).map(String.init)
        let format = lines.first(where: { $0.hasPrefix("format ") }) ?? ""
        guard let vertexLine = lines.first(where: { $0.hasPrefix("element vertex ") }),
              let vertexCount = Int(vertexLine.split(separator: " ").last ?? "") else {
            throw NSError(domain: "SplatPreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "El PLY no contiene vértices"])
        }
        let sampleEvery = max(1, Int(ceil(Double(vertexCount) / Double(maximumPoints))))
        if format.contains("binary_little_endian") {
            return try loadBinary(data, headerEnd: headerEnd, lines: lines, vertexCount: vertexCount, sampleEvery: sampleEvery)
        }
        if format.contains("ascii") {
            return try loadASCII(data, headerEnd: headerEnd, lines: lines, vertexCount: vertexCount, sampleEvery: sampleEvery)
        }
        throw NSError(domain: "SplatPreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "Formato PLY no compatible"])
    }

    private static func loadBinary(
        _ data: Data,
        headerEnd: Int,
        lines: [String],
        vertexCount: Int,
        sampleEvery: Int
    ) throws -> PLYPointCloud {
        let properties = vertexProperties(lines)
        let recordStride = properties.reduce(0) { $0 + $1.size }
        guard recordStride > 0, headerEnd + recordStride * vertexCount <= data.count else {
            throw NSError(domain: "SplatPreview", code: 5, userInfo: [NSLocalizedDescriptionKey: "Datos de vértices PLY incompletos"])
        }
        let propertyMap = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
        guard propertyMap["x"] != nil, propertyMap["y"] != nil, propertyMap["z"] != nil else {
            throw NSError(domain: "SplatPreview", code: 6, userInfo: [NSLocalizedDescriptionKey: "El PLY no contiene coordenadas x/y/z"])
        }
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        positions.reserveCapacity(min(vertexCount, 300_000))
        colors.reserveCapacity(min(vertexCount, 300_000))
        data.withUnsafeBytes { bytes in
            for index in Swift.stride(from: 0, to: vertexCount, by: sampleEvery) {
                let base = headerEnd + index * recordStride
                let position = SIMD3<Float>(
                    floatValue(bytes, base: base, property: propertyMap["x"]!),
                    floatValue(bytes, base: base, property: propertyMap["y"]!),
                    floatValue(bytes, base: base, property: propertyMap["z"]!)
                )
                guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { continue }
                positions.append(position)
                colors.append(color(bytes, base: base, properties: propertyMap))
            }
        }
        return finish(positions: positions, colors: colors, sourcePointCount: vertexCount)
    }

    private static func loadASCII(
        _ data: Data,
        headerEnd: Int,
        lines: [String],
        vertexCount: Int,
        sampleEvery: Int
    ) throws -> PLYPointCloud {
        let properties = vertexProperties(lines)
        let names = properties.map(\.name)
        guard let xIndex = names.firstIndex(of: "x"),
              let yIndex = names.firstIndex(of: "y"),
              let zIndex = names.firstIndex(of: "z") else {
            throw NSError(domain: "SplatPreview", code: 7, userInfo: [NSLocalizedDescriptionKey: "El PLY no contiene coordenadas x/y/z"])
        }
        let body = String(decoding: data[headerEnd...], as: UTF8.self)
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        for (index, line) in body.split(whereSeparator: \Character.isNewline).prefix(vertexCount).enumerated() where index % sampleEvery == 0 {
            let values = line.split(separator: " ").compactMap { Float($0) }
            guard values.count > max(xIndex, yIndex, zIndex) else { continue }
            positions.append(SIMD3(values[xIndex], values[yIndex], values[zIndex]))
            colors.append(asciiColor(values, names: names))
        }
        return finish(positions: positions, colors: colors, sourcePointCount: vertexCount)
    }

    private static func vertexProperties(_ lines: [String]) -> [Property] {
        var inVertices = false
        var offset = 0
        var result: [Property] = []
        for line in lines {
            if line.hasPrefix("element vertex ") { inVertices = true; continue }
            if inVertices && line.hasPrefix("element ") { break }
            guard inVertices, line.hasPrefix("property ") else { continue }
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count == 3, let size = scalarSize(parts[1]) else { continue }
            result.append(Property(name: parts[2], type: parts[1], offset: offset, size: size))
            offset += size
        }
        return result
    }

    private static func scalarSize(_ type: String) -> Int? {
        switch type {
        case "char", "int8", "uchar", "uint8": return 1
        case "short", "int16", "ushort", "uint16": return 2
        case "int", "int32", "uint", "uint32", "float", "float32": return 4
        case "double", "float64": return 8
        default: return nil
        }
    }

    private static func floatValue(_ bytes: UnsafeRawBufferPointer, base: Int, property: Property) -> Float {
        let offset = base + property.offset
        switch property.type {
        case "float", "float32":
            let bits = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            return Float(bitPattern: bits)
        case "double", "float64":
            let bits = UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            return Float(Double(bitPattern: bits))
        case "uchar", "uint8": return Float(bytes[offset])
        case "char", "int8": return Float(Int8(bitPattern: bytes[offset]))
        case "ushort", "uint16": return Float(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
        case "short", "int16": return Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
        case "uint", "uint32": return Float(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        default: return Float(Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self)))
        }
    }

    private static func color(
        _ bytes: UnsafeRawBufferPointer,
        base: Int,
        properties: [String: Property]
    ) -> SIMD4<Float> {
        if let red = properties["red"], let green = properties["green"], let blue = properties["blue"] {
            return SIMD4(
                normalizedColor(floatValue(bytes, base: base, property: red), type: red.type),
                normalizedColor(floatValue(bytes, base: base, property: green), type: green.type),
                normalizedColor(floatValue(bytes, base: base, property: blue), type: blue.type),
                1
            )
        }
        if let red = properties["f_dc_0"], let green = properties["f_dc_1"], let blue = properties["f_dc_2"] {
            let sh: Float = 0.2820948
            return SIMD4(
                clamp(0.5 + sh * floatValue(bytes, base: base, property: red)),
                clamp(0.5 + sh * floatValue(bytes, base: base, property: green)),
                clamp(0.5 + sh * floatValue(bytes, base: base, property: blue)),
                1
            )
        }
        return SIMD4(0.35, 0.75, 1.0, 1)
    }

    private static func normalizedColor(_ value: Float, type: String) -> Float {
        (type == "uchar" || type == "uint8") ? clamp(value / 255) : clamp(value)
    }

    private static func asciiColor(_ values: [Float], names: [String]) -> SIMD4<Float> {
        if let r = names.firstIndex(of: "red"), let g = names.firstIndex(of: "green"), let b = names.firstIndex(of: "blue"), values.count > max(r, g, b) {
            return SIMD4(clamp(values[r] / 255), clamp(values[g] / 255), clamp(values[b] / 255), 1)
        }
        if let r = names.firstIndex(of: "f_dc_0"), let g = names.firstIndex(of: "f_dc_1"), let b = names.firstIndex(of: "f_dc_2"), values.count > max(r, g, b) {
            let sh: Float = 0.2820948
            return SIMD4(clamp(0.5 + sh * values[r]), clamp(0.5 + sh * values[g]), clamp(0.5 + sh * values[b]), 1)
        }
        return SIMD4(0.35, 0.75, 1.0, 1)
    }

    private static func finish(
        positions: [SIMD3<Float>],
        colors: [SIMD4<Float>],
        sourcePointCount: Int
    ) -> PLYPointCloud {
        guard !positions.isEmpty else {
            return PLYPointCloud(positions: [], colors: [], sourcePointCount: sourcePointCount, center: .zero, radius: 1)
        }
        var minimum = positions[0]
        var maximum = positions[0]
        for position in positions.dropFirst() {
            minimum = min(minimum, position)
            maximum = max(maximum, position)
        }
        let center = (minimum + maximum) / 2
        let radius = max(length(maximum - minimum) / 2, 0.01)
        return PLYPointCloud(positions: positions, colors: colors, sourcePointCount: sourcePointCount, center: center, radius: radius)
    }

    private static func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
}
