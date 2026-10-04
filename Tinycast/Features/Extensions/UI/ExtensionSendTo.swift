import Foundation

enum ExtensionSendTo {
    static func payload(in screen: ExtensionScreen, at selection: Int) -> SendToPayload? {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        for action in actions {
            if let value = action.node.props["tinycastSendTo"], let payload = payload(value) {
                return payload
            }
        }
        switch screen.kind {
        case .detail:
            return screen.root?.string("markdown").flatMap(text)
        case .list:
            guard screen.items.indices.contains(selection) else { return nil }
            return screen.items[selection].node.node("detail")?.string("markdown").flatMap(text)
        case .form, .grid, .unsupported: return nil
        }
    }

    static func payload(_ value: RenderValue) -> SendToPayload? {
        if let object = value.objectValue {
            if let file = object["file"]?.stringValue { return filePayload(file) }
            return object["text"]?.stringValue.flatMap(text)
        }
        return value.stringValue.flatMap(text)
    }

    private static func filePayload(_ path: String) -> SendToPayload? {
        if path.hasPrefix("/"), !path.isEmpty { return .files([URL(fileURLWithPath: path)]) }
        guard let url = URL(string: path), url.isFileURL else { return nil }
        return .files([url])
    }

    private static func text(_ value: String) -> SendToPayload? {
        guard !value.isEmpty else { return nil }
        return .text(value)
    }
}
