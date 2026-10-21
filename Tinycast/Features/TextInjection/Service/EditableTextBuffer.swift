import AppKit
@preconcurrency import ApplicationServices

@MainActor
struct EditableTextBuffer {
    let app: NSRunningApplication
    let element: AXUIElement
    let text: String
    let selection: NSRange

    static func capture(in app: NSRunningApplication) -> EditableTextBuffer? {
        guard let element = AccessibilityText.focusedElement(in: app),
            !AccessibilityText.usesTextMarkerSelection(element),
            let role = attribute(kAXRoleAttribute, in: element) as? String,
            [kAXTextAreaRole, kAXTextFieldRole].contains(role),
            attribute(kAXSubroleAttribute, in: element) as? String != kAXSecureTextFieldSubrole,
            attribute(kAXEnabledAttribute, in: element) as? Bool != false,
            let text = AccessibilityText.stringValue(in: element),
            let count = attribute(kAXNumberOfCharactersAttribute, in: element) as? NSNumber,
            count.intValue == text.utf16.count,
            text.utf16.count <= 1_000_000,
            let selection = AccessibilityText.selectedRange(in: element), Range(selection, in: text) != nil
        else { return nil }
        guard AccessibilityText.isAttributeSettable(kAXSelectedTextRangeAttribute, in: element),
            AccessibilityText.isAttributeSettable(kAXSelectedTextAttribute, in: element)
                || AccessibilityText.isAttributeSettable(kAXValueAttribute, in: element)
        else { return nil }
        if let ranges = attribute(kAXSelectedTextRangesAttribute, in: element) as? [Any], ranges.count > 1 {
            return nil
        }
        return EditableTextBuffer(app: app, element: element, text: text, selection: selection)
    }

    var observedText: String? { AccessibilityText.stringValue(in: element) }

    func matches(selection expected: NSRange) -> Bool {
        guard !app.isTerminated,
            let focused = AccessibilityText.focusedElement(in: app), CFEqual(focused, element)
        else { return false }
        return observedText == text && AccessibilityText.selectedRange(in: element) == expected
    }

    @discardableResult
    func select(_ range: NSRange) -> Bool {
        AccessibilityText.setSelectedRange(range, in: element)
            && AccessibilityText.selectedRange(in: element) == range
    }

    private static func attribute(_ name: String, in element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

}
