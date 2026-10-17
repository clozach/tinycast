import Foundation
@preconcurrency import ApplicationServices

/// Reads one window's chrome for a playing-tab marker, never its page content.
enum WindowAudioScanner {
    private static let timeout: Float = 0.2
    private static let maxDepth = 14
    private static let maxNodes = 600
    nonisolated(unsafe) private static let attributes = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute,
    ] as CFArray

    nonisolated static func probe(_ window: AXUIElement) -> WindowAudioProbe {
        AXUIElementSetMessagingTimeout(window, timeout)
        var probe = WindowAudioProbe()
        var queue = [(window, 0)]
        var index = 0
        while index < queue.count, index < maxNodes {
            let (element, depth) = queue[index]
            index += 1
            let node = read(element)
            if node.role == "AXRadioButton" { probe.hasTabStrip = true }
            if [node.title, node.label].contains(where: AudioMarker.indicatesAudio) {
                probe.hasMarker = true
                return probe
            }
            guard node.role != "AXWebArea", depth < maxDepth else { continue }
            queue += node.children.map { ($0, depth + 1) }
        }
        return probe
    }

    private nonisolated static func read(_ element: AXUIElement)
        -> (role: String, title: String, label: String, children: [AXUIElement])
    {
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values)
        guard status == .success, let list = values as? [Any], list.count == 4 else { return ("", "", "", []) }
        return (
            list[0] as? String ?? "", list[1] as? String ?? "", list[2] as? String ?? "",
            list[3] as? [AXUIElement] ?? [])
    }
}

/// One window to scan. AX elements are thread-safe CF objects, so crossing actors is sound.
struct WindowAudioTarget: @unchecked Sendable {
    let handle: Int
    let processID: pid_t
    let window: AXUIElement
}
