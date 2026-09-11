import AppKit

/// Preview windows deliberately have no history accept/paste keyboard route.
final class PreviewPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func handleClose(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53,
              (firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        if !event.isARepeat { onEscape?() }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleClose(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if handleClose(event) { return }
        super.sendEvent(event)
    }
}
