import AppKit
import ClipboardCore

/// Records only while explicitly focused. No global keyboard event monitor.
final class ShortcutRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var isRecording = false
    var shortcut: KeyboardShortcut = .default { didSet { updateLabel() } }
    var onChange: ((KeyboardShortcut) -> Void)?
    var onMessage: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 62)
        ])
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        updateLabel()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool { beginRecording(); return true }
    override func mouseDown(with event: NSEvent) { beginRecording() }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func resignFirstResponder() -> Bool { stopRecording(); return true }

    func beginRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
        updateLabel()
        onMessage?("按下新的组合键；Esc 取消录制。")
    }
    func stopRecording() { isRecording = false; updateLabel() }

    @discardableResult
    func capture(_ event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        if event.isARepeat { return true }
        if event.keyCode == 53 { stopRecording(); onMessage?("已取消录制，候选快捷键未改变。"); return true }
        var modifiers: KeyboardShortcut.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        record(KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        return true
    }

    func record(_ value: KeyboardShortcut) {
        guard isRecording else { return }
        do { try ShortcutConflictPolicy.validate(value) }
        catch { onMessage?(error.localizedDescription); return }
        shortcut = value
        stopRecording()
        onChange?(value)
        onMessage?("已录制 \(value.displayName)，点击保存检查占用并生效。")
    }

    private func updateLabel() {
        label.stringValue = isRecording ? "按下组合键…" : shortcut.displayName
        layer?.backgroundColor = (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        setAccessibilityLabel("快捷键录制：\(label.stringValue)")
    }
}

final class ShortcutPreferencesWindow: NSWindow {
    weak var recorder: ShortcutRecorderView?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recorder?.capture(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func sendEvent(_ event: NSEvent) {
        if recorder?.capture(event) == true { return }
        super.sendEvent(event)
    }
}
