import AppKit
import ClipboardCore

/// Clip the actual material, not just the decorative border. Visual-effect
/// backgrounds have their own compositing layer and also need an alpha mask.
final class RoundedPanelView: NSVisualEffectView {
    static let radius: CGFloat = 16
    private var maskSize = NSSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .circular
        layer?.masksToBounds = true
        // A separate layer border can leave a light fringe outside the material.
        layer?.borderWidth = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        guard bounds.size != maskSize, bounds.width > 0, bounds.height > 0 else { return }
        maskSize = bounds.size
        maskImage = NSImage(size: maskSize, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius).fill()
            return true
        }
        window?.invalidateShadow()
    }
}
