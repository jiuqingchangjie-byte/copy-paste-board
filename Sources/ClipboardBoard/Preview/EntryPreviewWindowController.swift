import AppKit
import ClipboardCore

/// Owns one preview surface. Pinning detaches this same window, preserving zoom.
final class EntryPreviewWindowController: NSWindowController, NSWindowDelegate {
    let entryID: UUID
    let contentController: NSViewController
    private(set) var isPinned = false
    var onClose: (() -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onResignKey: (() -> Void)?
    private var pinButton: NSButton?

    init?(entry: HistoryEntry, onCopyText: @escaping (String) -> Bool) {
        entryID = entry.id
        let title: String
        switch entry.payload {
        case .image(let data):
            guard let image = ImagePreviewViewController(data: data) else { return nil }
            contentController = image
            title = L10n.tr("查看原图")
        case .text(let text):
            let content = TextPreviewViewController(text: text)
            content.onCopyText = onCopyText
            contentController = content
            title = L10n.tr("完整文本")
        case .files(let urls):
            let content = TextPreviewViewController(text: urls.compactMap { URL(string: $0)?.path }.joined(separator: "\n"),
                                                    allowsJSONFormatting: false)
            content.onCopyText = onCopyText
            contentController = content
            title = L10n.tr("完整文件路径")
        }
        let panel = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = title
        panel.setAccessibilityLabel(title)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.minSize = NSSize(width: 470, height: 250)
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.requestClose() }
        let root = NSView()
        let hint = NSTextField(labelWithString: L10n.tr("esc 关闭预览并返回原选择"))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let header = NSStackView(views: [hint, NSView()])
        if case .image = entry.payload {
            let pin = NSButton(title: L10n.tr("置顶固定"), target: self, action: #selector(togglePin))
            pin.bezelStyle = .rounded
            pin.setAccessibilityLabel(L10n.tr("置顶固定图片"))
            header.addArrangedSubview(pin)
            pinButton = pin
        }
        let dragHandle = DraggableHeaderView()
        dragHandle.toolTip = L10n.tr("拖动这里移动预览")
        header.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: dragHandle.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: dragHandle.trailingAnchor),
            header.topAnchor.constraint(equalTo: dragHandle.topAnchor),
            header.bottomAnchor.constraint(equalTo: dragHandle.bottomAnchor)
        ])
        let stack = NSStackView(views: [dragHandle, contentController.view])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        panel.contentView = root
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(relativeTo anchor: NSRect, parent: NSWindow, takeFocus: Bool) {
        guard let window else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? parent.screen
        if let screen {
            window.setFrame(Self.anchoredFrame(size: window.frame.size, anchor: anchor, visibleFrame: screen.visibleFrame), display: true)
        }
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        // Fit only after the window has its final on-screen content bounds.
        (contentController as? ImagePreviewViewController)?.fitToWindow()
        if takeFocus {
            window.makeKey()
            focusContent()
        }
    }

    func focusContent() {
        if let text = contentController as? TextPreviewViewController { window?.makeFirstResponder(text.textView) }
        else if let image = contentController as? ImagePreviewViewController { window?.makeFirstResponder(image.scrollView) }
    }

    static func anchoredFrame(size: NSSize, anchor: NSRect, visibleFrame: NSRect) -> NSRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let right = anchor.maxX + 8
        let x = right + width <= visibleFrame.maxX ? right : anchor.minX - width - 8
        return NSRect(x: min(max(x, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(anchor.maxY - height, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }

    @objc func togglePin() {
        guard pinButton != nil else { return }
        isPinned.toggle()
        if isPinned, let window { window.parent?.removeChildWindow(window) }
        // Unpinning keeps it as a normal independent viewer until closed.
        window?.level = isPinned ? .floating : .normal
        pinButton?.title = isPinned ? L10n.tr("取消置顶") : L10n.tr("置顶固定")
        pinButton?.state = isPinned ? .on : .off
        onPinChanged?(isPinned)
    }

    func requestClose() { onClose?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { requestClose(); return false }
    func windowDidResignKey(_ notification: Notification) { onResignKey?() }

    func hide() {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }
}
