import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute keys are constant C globals.
@preconcurrency import ApplicationServices

/// Always against a named process: the system-wide focus answers with ours.
enum AccessibilityText {
    /// Generous for a responsive app, short enough that a wedged one can't stall the main actor.
    private static let timeout: Float = 1

    /// The two have different fixes; collapsing them tells a reader to select what they selected.
    enum Selection: Equatable {
        case text(String)
        case noFocusedElement
        case empty
    }

    static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Per element and never inherited, so the focused element needs its own against a hang.
        AXUIElementSetMessagingTimeout(application, timeout)
        activateManualAccessibility(of: application)
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func read(in app: NSRunningApplication) -> Selection {
        guard let element = focusedElement(in: app) else { return .noFocusedElement }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value)
        if status == .success, let text = value as? String, !text.isEmpty { return .text(text) }
        guard let web = webSelection(in: element), !web.isEmpty else { return .empty }
        return .text(web)
    }

    /// A narrower question, for callers that can act on the text but not on why there is none.
    static func selection(in app: NSRunningApplication) -> String? {
        guard case .text(let text) = read(in: app) else { return nil }
        return text
    }

    /// Chromium builds its tree only once asked, so Chrome and Electron answer nothing until this.
    private static func activateManualAccessibility(of application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Browsers have no `AXSelectedText`: web selection exists only as an opaque marker range.
    private static func webSelection(in element: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextMarkerRangeAttribute as CFString,
                &range) == .success,
            let range,
            CFGetTypeID(range) == AXTextMarkerRangeGetTypeID()
        else { return nil }

        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
                range,
                &value) == .success
        else { return nil }
        return value as? String
    }

    static func usesTextMarkerSelection(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextMarkerRangeAttribute as CFString,
                &value) == .success,
            let value
        else { return false }
        return CFGetTypeID(value) == AXTextMarkerRangeGetTypeID()
    }

    static func stringValue(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &value) == .success
        else { return nil }
        return value as? String
    }

    static func selectedRange(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range),
            range.location >= 0, range.length >= 0, range.location <= Int.max - range.length
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func setSelectedRange(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value) == .success
    }

    static func isAttributeSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                element,
                attribute as CFString,
                &settable) == .success
        else { return false }
        return settable.boolValue
    }
}
