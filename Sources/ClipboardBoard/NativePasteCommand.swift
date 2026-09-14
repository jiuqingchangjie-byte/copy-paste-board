import AppKit
import ApplicationServices

struct PasteCapabilities {
    let accessibility: Bool
    let eventPosting: Bool
    var canPaste: Bool { accessibility || eventPosting }
}

enum PasteDelivery { case submitted, unavailable, uncertain }
enum MenuPasteResult { case performed, notAvailable, disabled, uncertain }

protocol PasteCommandBackend {
    var capabilities: PasteCapabilities { get }
    var frontmostPID: pid_t? { get }
    var keysAreReleased: Bool { get }
    var clipboardChangeCount: Int { get }
    func pressPasteMenu(in pid: pid_t) -> MenuPasteResult
    func postPasteShortcut() -> Bool
}

enum NativePasteCommand {
    static func deliver(to pid: pid_t, using backend: PasteCommandBackend) -> PasteDelivery {
        let access = backend.capabilities
        let clipboardVersion = backend.clipboardChangeCount
        if access.accessibility {
            switch backend.pressPasteMenu(in: pid) {
            case .performed: return .submitted
            case .uncertain: return .uncertain // Never send a second paste after a possible timeout.
            // Custom editors can handle Command-V while their native menu stays
            // disabled. Neither result has performed an action, so one keyboard
            // attempt is safe; an AX success or timeout must never fall through.
            case .disabled, .notAvailable: break
            }
        }
        // AX menu traversal can take time. Recheck the live permissions, focus,
        // physical keys and clipboard before sending a global keyboard event.
        guard backend.capabilities.eventPosting,
              backend.frontmostPID == pid,
              backend.keysAreReleased,
              backend.clipboardChangeCount == clipboardVersion else { return .unavailable }
        return backend.postPasteShortcut() ? .submitted : .unavailable
    }
}

/// Stores only UI references, never the input field's text or clipboard contents.
final class OriginalInputFocus {
    private var pid: pid_t?
    private var focusedWindow: AXUIElement?
    private var focusedElement: AXUIElement?

    func capture(in pid: pid_t?) {
        self.pid = pid
        focusedWindow = nil
        focusedElement = nil
        guard let pid, AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        focusedWindow = AXRead.element(app, kAXFocusedWindowAttribute)
        focusedElement = AXRead.element(app, kAXFocusedUIElementAttribute)
    }

    func restore(in pid: pid_t) -> Bool {
        guard self.pid == pid, let focusedElement, AXIsProcessTrusted() else { return true }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        if let focusedWindow { _ = AXUIElementPerformAction(focusedWindow, kAXRaiseAction as CFString) }
        if let current = AXRead.element(app, kAXFocusedUIElementAttribute), CFEqual(current, focusedElement) { return true }
        var canSet = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(focusedElement, kAXFocusedAttribute as CFString, &canSet) == .success,
              canSet.boolValue else { return false }
        return AXUIElementSetAttributeValue(focusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }
}

enum AccessibilityPasteMenu {
    static func perform(in pid: pid_t) -> MenuPasteResult {
        guard AXIsProcessTrusted() else { return .notAvailable }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let bar = AXRead.element(app, kAXMenuBarAttribute) else { return .notAvailable }
        let top = AXRead.children(bar)
        let editTitles = Set(["Edit", "编辑", "編輯", "編集", "편집", "Bearbeiten", "Édition", "Editar", "Modifica"])
        let preferred = top.filter { editTitles.contains(AXRead.value($0, kAXTitleAttribute) as? String ?? "") }
        let pasteTitles = Set(["Paste", "粘贴", "貼上", "粘貼", "貼り付け", "ペースト", "붙여넣기", "Einfügen", "Coller", "Pegar", "Incolla"])
        let others = top.filter { item in !preferred.contains { CFEqual($0, item) } }
        var stack = (preferred + others).reversed().map { ($0, 0) }
        let deadline = Date().addingTimeInterval(1)
        var visited = 0
        while let (element, depth) = stack.popLast(), visited < 240, Date() < deadline {
            visited += 1
            let key = (AXRead.value(element, kAXMenuItemCmdCharAttribute) as? String)?.lowercased()
            let modifiers = (AXRead.value(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
            let title = (AXRead.value(element, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // AX uses 0 for the default Command modifier, not for an unmodified key.
            if (key == "v" && modifiers == 0) || pasteTitles.contains(title) {
                guard let enabled = (AXRead.value(element, kAXEnabledAttribute) as? NSNumber)?.boolValue else { continue }
                guard enabled else { return .disabled }
                switch AXUIElementPerformAction(element, kAXPressAction as CFString) {
                case .success: return .performed
                case .actionUnsupported, .notImplemented, .invalidUIElement, .illegalArgument: return .notAvailable
                default: return .uncertain
                }
            }
            if depth < 4 { stack.append(contentsOf: AXRead.children(element).reversed().map { ($0, depth + 1) }) }
        }
        return .notAvailable
    }
}

private enum AXRead {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
