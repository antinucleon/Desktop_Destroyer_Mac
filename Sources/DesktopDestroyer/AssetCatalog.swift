import AppKit

enum AssetCatalog {
    static func url(for filename: String) -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(filename),
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Resources/Assets/generated", isDirectory: true)
                .appendingPathComponent(filename)
        ]
        return candidates.compactMap { $0 }.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func image(named filename: String) -> NSImage? {
        guard let url = url(for: filename) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func soundURL(for filename: String) -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("Sounds", isDirectory: true)
                .appendingPathComponent(filename),
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Resources/Sounds", isDirectory: true)
                .appendingPathComponent(filename)
        ]
        return candidates.compactMap { $0 }.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func toolThumbnail(for tool: DestructionTool) -> NSImage? {
        if let standaloneName = tool.standaloneCursorAssetName,
           let standalone = image(named: standaloneName) {
            standalone.size = NSSize(width: 48, height: 48)
            return standalone
        }
        guard let source = image(named: "tool-cursors.png"),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let cellWidth = cgImage.width / 3
        let cellHeight = cgImage.height / 3
        let column = Int(tool.rawValue) % 3
        let row = Int(tool.rawValue) / 3
        let crop = CGRect(
            x: column * cellWidth,
            y: row * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: 48, height: 48))
    }
}
