import AppKit

final class DraggableHeaderView: NSView {
    var onDragFinished: ((NSPoint) -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // Clear/menu buttons remain clickable; the title, icon and gaps are handles.
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton { return hit }
            view = current.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.performDrag(with: event)
        onDragFinished?(window.frame.origin)
    }
}
