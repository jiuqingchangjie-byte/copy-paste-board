import AppKit
import ClipboardCore

/// Edits a candidate; registration/persistence remain an injected app action.
final class ShortcutPreferencesController: NSWindowController, NSWindowDelegate {
    let recorder = ShortcutRecorderView()
    private let currentLabel = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var save: ((KeyboardShortcut) throws -> Void)?
    var isVisible: Bool { window?.isVisible == true }

    init() {
        let window = ShortcutPreferencesWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 345),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L10n.tr("自定义快捷键")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.recorder = recorder
        let title = NSTextField(labelWithString: L10n.tr("打开 / 关闭剪贴板历史"))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: L10n.tr("点击录制，再按组合键。至少包含 ⌘、⌥、⌃ 之一。\n按键按键盘位置保存，字母标识以美式键盘为准。"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let record = NSButton(title: L10n.tr("录制快捷键"), target: self, action: #selector(beginRecording))
        let reset = NSButton(title: L10n.tr("恢复默认 ⌥V"), target: self, action: #selector(restoreDefault))
        let saveButton = NSButton(title: L10n.tr("保存"), target: self, action: #selector(saveShortcut))
        saveButton.keyEquivalent = "\r"
        let cancel = NSButton(title: L10n.tr("取消"), target: self, action: #selector(cancelEditing))
        cancel.keyEquivalent = "\u{1b}"
        [record,reset,saveButton,cancel].forEach { $0.bezelStyle = .rounded }
        let actions = NSStackView(views: [record,reset,NSView(),cancel,saveButton])
        actions.spacing = 8
        message.font = .systemFont(ofSize: 12)
        message.maximumNumberOfLines = 3
        message.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        currentLabel.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [title,currentLabel,recorder,hint,message,actions])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        window.contentView = root
        for label in [title, currentLabel, hint, message] {
            label.alignment = .left
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        recorder.onMessage = { [weak self] text in self?.showMessage(text, error: false) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(current: KeyboardShortcut, isRegistered: Bool, save: @escaping (KeyboardShortcut) throws -> Void) {
        self.save = save
        recorder.stopRecording()
        recorder.shortcut = current
        currentLabel.stringValue = L10n.tr("当前设置：{0}{1}", String(describing: current.displayName), String(describing: isRegistered ? L10n.tr(" · 已生效") : L10n.tr(" · 未注册，可重新设置")))
        showMessage(L10n.tr("保存成功后新快捷键立即生效；失败时保留原快捷键。"), error: false)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func receiveRegisteredShortcut(_ shortcut: KeyboardShortcut) { recorder.record(shortcut) }
    @objc func beginRecording() { recorder.beginRecording() }
    @objc func restoreDefault() {
        recorder.stopRecording()
        recorder.shortcut = .default
        showMessage(L10n.tr("已选择默认 ⌥V，点击保存后生效。"), error: false)
    }
    @objc func saveShortcut() {
        guard !recorder.isRecording else { return }
        do {
            try save?(recorder.shortcut)
            close()
        } catch { showMessage(error.localizedDescription, error: true) }
    }
    @objc func cancelEditing() { close() }
    func windowWillClose(_ notification: Notification) { recorder.stopRecording(); save = nil }
    func windowDidResignKey(_ notification: Notification) { recorder.stopRecording() }
    private func showMessage(_ text: String, error: Bool) {
        message.stringValue = text
        message.textColor = error ? .systemRed : .secondaryLabelColor
    }
}
