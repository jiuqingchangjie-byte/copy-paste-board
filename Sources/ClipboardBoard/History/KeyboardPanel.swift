import ClipboardCore
import AppKit

final class KeyboardPanel: NSPanel {
    var onMove: ((Int) -> Void)?
    var onAccept: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?
    var onKeyboardRoute: ((String) -> Void)?
    var onPreview: (() -> Void)?
    var isPreviewOpen: (() -> Bool)?
    private var compositionEventTimestamp: TimeInterval?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func isComposing(for event: NSEvent?) -> Bool {
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return true }
        return event.map { $0.timestamp == compositionEventTimestamp } ?? false
    }

    private func handleHistoryKey(_ event: NSEvent, route: String) -> Bool {
        guard event.type == .keyDown else { return false }
        if (firstResponder as? NSTextView)?.hasMarkedText() == true {
            compositionEventTimestamp = event.timestamp
            return false
        }
        guard !isComposing(for: event) else { return false }
        if event.keyCode == 49 {
            // Search owns spaces, including while an input method is active.
            guard !(firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
            if !event.isARepeat { onPreview?() }
            return true
        }
        if isPreviewOpen?() == true, [UInt16(125), 126, 36, 76, 51].contains(event.keyCode) {
            return true
        }
        switch event.keyCode {
        case 125: onMove?(1)
        case 126: onMove?(-1)
        case 36, 76:
            onKeyboardRoute?(L10n.tr("{0}：回车{1}", String(describing: route), String(describing: event.isARepeat ? L10n.tr("重复已忽略") : L10n.tr("已接收"))))
            if !event.isARepeat { onAccept?() }
        case 53: onEscape?()
        case 51 where event.modifierFlags.contains(.command): onDelete?()
        default: return false
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit may dispatch Return through key-equivalent processing before
        // NSWindow.sendEvent, particularly while a search field owns focus.
        if handleHistoryKey(event, route: L10n.tr("快捷键分发")) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if handleHistoryKey(event, route: L10n.tr("窗口按键")) { return }
        super.sendEvent(event)
    }
}
