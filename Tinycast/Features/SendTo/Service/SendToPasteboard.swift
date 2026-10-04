import AppKit
import CryptoKit

extension SendToService {
    static func snapshot(
        from pasteboard: NSPasteboard = .general, stagingDirectory: URL? = nil
    ) throws -> SendToPayload? {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> [String: Data]? in
            var types: [String: Data] = [:]
            for type in item.types where type.rawValue != "com.tinycast.internal" {
                if let data = item.data(forType: type) { types[type.rawValue] = data }
            }
            return types.isEmpty ? nil : types
        }
        guard !items.isEmpty else { return nil }
        let files = items.compactMap { string(.fileURL, in: $0).flatMap(URL.init(string:)) }.filter(\.isFileURL)
        if !files.isEmpty && files.count == items.count {
            return .pasteboard(.init(items: items, openItems: files, displayTitle: SendToPayload.files(files).displayTitle))
        }
        if items.count == 1, let first = items.first {
            if let type = [NSPasteboard.PasteboardType.png, .tiff].first(where: { first[$0.rawValue] != nil }),
               let data = first[type.rawValue] {
                let url = try materialize(data, extension: type == .png ? "png" : "tiff", directory: stagingDirectory)
                return .pasteboard(.init(items: items, openItems: [url], displayTitle: "Clipboard image"))
            }
            let text = string(.URL, in: first) ?? string(.string, in: first)
            let urls = text.flatMap(SendToPayload.link(in:)).map { [$0] } ?? []
            let title = text.map { SendToPayload.text($0).displayTitle } ?? "Clipboard content"
            return .pasteboard(.init(items: items, openItems: urls, displayTitle: title))
        }
        return .pasteboard(.init(items: items, openItems: [], displayTitle: "\(items.count) clipboard items"))
    }

    static func write(_ payload: SendToPayload, to pasteboard: NSPasteboard = .general) throws {
        try validate(payload)
        let items: [[String: Data]]
        switch payload {
        case .text(let text): items = [[NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)]]
        case .files(let urls):
            items = urls.map { [
                NSPasteboard.PasteboardType.fileURL.rawValue: Data($0.absoluteString.utf8),
                NSPasteboard.PasteboardType.string.rawValue: Data($0.path.utf8)
            ] }
        case .image(let url): items = [try imageRepresentation(at: url)]
        case .pasteboard(let snapshot): items = snapshot.items
        }
        let objects = try items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in types {
                guard item.setData(data, forType: .init(rawType)) else { throw SendToError.clipboardWrite }
            }
            item.setData(Data(), forType: .init("com.tinycast.internal"))
            return item
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else { throw SendToError.clipboardWrite }
    }

    private static func string(_ type: NSPasteboard.PasteboardType, in item: [String: Data]) -> String? {
        item[type.rawValue].flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func imageRepresentation(at url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if url.pathExtension.lowercased() == "png" { return [NSPasteboard.PasteboardType.png.rawValue: data] }
        if ["tif", "tiff"].contains(url.pathExtension.lowercased()) {
            return [NSPasteboard.PasteboardType.tiff.rawValue: data]
        }
        guard let image = NSBitmapImageRep(data: data), let tiff = image.tiffRepresentation else {
            throw SendToError.unreadableImage(url.lastPathComponent)
        }
        return [NSPasteboard.PasteboardType.tiff.rawValue: tiff]
    }

    private static func materialize(_ data: Data, extension suffix: String, directory root: URL?) throws -> URL {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let root = root ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "tinycast", isDirectory: true)
            .appendingPathComponent("SendTo", isDirectory: true)
        try removeExpiredImages(in: root, now: Date())
        let directory = root.appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Clipboard Image.\(suffix)")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func removeExpiredImages(in directory: URL, now: Date) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        for child in children {
            let name = child.lastPathComponent
            guard name.count == 64, name.allSatisfy(\.isHexDigit) else { continue }
            let values = try child.resourceValues(forKeys: keys)
            guard values.isDirectory == true, let date = values.contentModificationDate,
                  now.timeIntervalSince(date) > 24 * 60 * 60 else { continue }
            try FileManager.default.removeItem(at: child)
        }
    }
}
