import AppKit

enum LogoStore {
    private static let maxEdge: CGFloat = 256

    static func load(_ fileName: String?, in directory: URL) -> NSImage? {
        guard let fileName, !fileName.isEmpty else {
            return nil
        }
        let url = fileName.hasPrefix("/")
            ? URL(fileURLWithPath: fileName)
            : directory.appendingPathComponent(fileName)
        return NSImage(contentsOf: url)
    }

    /// Scales to at most 256 px and writes `<id>.png`; returns the relative file name.
    static func save(_ image: NSImage, for id: UUID, in directory: URL) throws -> String {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height, 1))
        let target = NSSize(width: max(1, round(size.width * scale)), height: max(1, round(size.height * scale)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = "\(id.uuidString.lowercased()).png"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Deletes only files inside the logos directory, never user-supplied absolute paths.
    static func delete(_ fileName: String, in directory: URL) {
        guard !fileName.hasPrefix("/"), !fileName.contains("..") else {
            return
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
