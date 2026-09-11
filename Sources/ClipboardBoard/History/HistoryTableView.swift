import AppKit

/// Pointer tracking and contextual actions stay separate from history data.
final class HistoryTableView: NSTableView {
    var onHoverRow: ((Int) -> Void)?
    var onCancelHover: (() -> Void)?
    var contextMenuForRow: ((Int) -> NSMenu?)?
    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverRow?(row(at: convert(event.locationInWindow, from: nil)))
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { onCancelHover?() }
    override func mouseDown(with event: NSEvent) {
        onCancelHover?()
        super.mouseDown(with: event)
    }
    override func scrollWheel(with event: NSEvent) {
        onCancelHover?()
        super.scrollWheel(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onCancelHover?()
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        // macOS secondary click covers both mouse right-click and trackpad
        // two-finger click. Do not select/paste as a side effect of opening it.
        return contextMenuForRow?(row)
    }
}
