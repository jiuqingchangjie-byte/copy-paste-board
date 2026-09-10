import AppKit
import ClipboardCore

/// Clip the actual material, not just the decorative border. Visual-effect
/// backgrounds have their own compositing layer and also need an alpha mask.
private final class RoundedPanelView: NSVisualEffectView {
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

private final class DraggableHeaderView: NSView {
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

final class KeyboardPanel: NSPanel {
    var onMove: ((Int) -> Void)?
    var onAccept: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            if !composing {
                switch event.keyCode {
                case 125: onMove?(1); return
                case 126: onMove?(-1); return
                case 36, 76: if !event.isARepeat { onAccept?() }; return
                case 53: onEscape?(); return
                case 51 where event.modifierFlags.contains(.command): onDelete?(); return
                default: break
                }
            }
        }
        super.sendEvent(event)
    }
}

final class HistoryPanelController: NSWindowController, NSWindowDelegate, NSTableViewDataSource,
                                     NSTableViewDelegate, NSSearchFieldDelegate {
    private let table = NSTableView()
    private let search = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "0 条记录")
    private let emptyTitle = NSTextField(labelWithString: "你的下一次复制，会出现在这里")
    private let emptySubtitle = NSTextField(labelWithString: "先用 ⌘C 复制，再用 ⌥V 找回。")
    private let permissionRow = NSStackView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "↑ ↓ 选择    ↩ 粘贴    esc 关闭")
    private var allEntries: [HistoryEntry] = []
    private var filteredEntries: [HistoryEntry] = []
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var isShowingMenu = false
    private var draggedOrigin: NSPoint?
    var onPaste: ((HistoryEntry) -> Void)?
    var onDeleteEntry: ((UUID) -> Void)?
    var onPermission: (() -> Void)?
    var onMenu: ((NSView) -> Void)?
    var onClear: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onOriginChanged: ((NSPoint) -> Void)?

    init(origin: NSPoint? = nil) {
        draggedOrigin = origin
        let panel = KeyboardPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 490),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "剪贴板历史"
        panel.setAccessibilityLabel("剪贴板历史")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.onMove = { [weak self] in self?.moveSelection($0) }
        panel.onAccept = { [weak self] in self?.acceptSelection() }
        panel.onEscape = { [weak self] in self?.dismiss() }
        panel.onDelete = { [weak self] in self?.deleteSelection() }
        buildView(panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var isVisible: Bool { window?.isVisible == true }

    private func buildView(_ panel: NSPanel) {
        let root = RoundedPanelView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = root

        let icon = NSImageView(image: NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .controlAccentColor
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let title = NSTextField(labelWithString: "剪贴板")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        let titleColumn = NSStackView(views: [title, countLabel])
        titleColumn.orientation = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = 3
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        let clearButton = NSButton(title: "全部清空", target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 12)
        clearButton.contentTintColor = .controlAccentColor
        let menuButton = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "更多选项")!,
                                  target: self, action: #selector(showMenu(_:)))
        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.setAccessibilityLabel("更多选项")
        let headerContent = NSStackView(views: [icon, titleColumn, NSView(), clearButton, menuButton])
        headerContent.spacing = 10
        headerContent.alignment = .centerY
        let header = DraggableHeaderView()
        header.toolTip = "拖动这里移动剪贴板"
        header.onDragFinished = { [weak self] origin in
            self?.draggedOrigin = origin
            self?.onOriginChanged?(origin)
        }
        headerContent.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerContent)
        NSLayoutConstraint.activate([
            headerContent.topAnchor.constraint(equalTo: header.topAnchor),
            headerContent.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerContent.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerContent.trailingAnchor.constraint(equalTo: header.trailingAnchor)
        ])

        search.placeholderString = "搜索内容或来源应用"
        search.font = .systemFont(ofSize: 14)
        search.controlSize = .large
        search.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("搜索剪贴板历史")
        search.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 78
        table.intercellSpacing = NSSize(width: 0, height: 8)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.focusRingType = .none
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.setAccessibilityLabel("剪贴板历史记录，使用上下键选择，回车粘贴")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let listArea = NSView()
        listArea.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: listArea.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listArea.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: listArea.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listArea.trailingAnchor)
        ])

        emptyTitle.font = .systemFont(ofSize: 15, weight: .medium)
        emptyTitle.textColor = .secondaryLabelColor
        emptySubtitle.font = .systemFont(ofSize: 12)
        emptySubtitle.textColor = .tertiaryLabelColor
        let empty = NSStackView(views: [emptyTitle, emptySubtitle])
        empty.orientation = .vertical
        empty.spacing = 10
        empty.translatesAutoresizingMaskIntoConstraints = false
        listArea.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: listArea.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: listArea.centerYAnchor, constant: -16)
        ])

        let permissionText = NSTextField(labelWithString: "允许辅助功能，即可回车粘贴到原应用")
        permissionText.font = .systemFont(ofSize: 11)
        permissionText.textColor = .secondaryLabelColor
        let permissionButton = NSButton(title: "去授权", target: self, action: #selector(requestPermission))
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small
        permissionRow.setViews([permissionText, NSView(), permissionButton], in: .leading)
        permissionRow.alignment = .centerY
        permissionRow.spacing = 8
        permissionRow.heightAnchor.constraint(equalToConstant: 30).isActive = true

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .systemOrange
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.isHidden = true
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        let localLabel = NSTextField(labelWithString: "仅存于本机")
        localLabel.font = .systemFont(ofSize: 10)
        localLabel.textColor = .tertiaryLabelColor
        let footer = NSStackView(views: [footerLabel, NSView(), localLabel])
        footer.alignment = .centerY

        let divider = NSBox()
        divider.boxType = .separator
        let stack = NSStackView(views: [header, search, listArea, divider, permissionRow, messageLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            listArea.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }

    func present(entries: [HistoryEntry], hasPermission: Bool, paused: Bool) {
        allEntries = entries
        search.stringValue = ""
        messageLabel.isHidden = true
        updatePermission(hasPermission)
        countLabel.stringValue = "\(entries.count) 条记录\(paused ? " · 已暂停" : "")"
        reload(keepingSelection: false)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let window {
            if let origin = draggedOrigin,
               let savedScreen = NSScreen.screens.first(where: {
                   $0.visibleFrame.contains(NSPoint(x: origin.x + window.frame.width / 2,
                                                   y: origin.y + window.frame.height / 2))
               }) {
                let frame = savedScreen.visibleFrame
                window.setFrameOrigin(NSPoint(
                    x: min(max(origin.x, frame.minX), frame.maxX - window.frame.width),
                    y: min(max(origin.y, frame.minY), frame.maxY - window.frame.height)))
            } else if let frame = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2,
                                              y: frame.midY - window.frame.height / 2 + 40))
            }
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.isShowingMenu == false { self?.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.isShowingMenu == false, event.window !== self?.window { self?.dismiss() }
            return event
        }
    }

    func update(entries: [HistoryEntry], paused: Bool) {
        allEntries = entries
        countLabel.stringValue = "\(entries.count) 条记录\(paused ? " · 已暂停" : "")"
        reload(keepingSelection: true)
    }

    func updatePermission(_ allowed: Bool) {
        permissionRow.isHidden = allowed
        footerLabel.stringValue = "↑ ↓ 选择    ↩ 粘贴    esc 关闭"
    }

    func showMessage(_ text: String) {
        messageLabel.stringValue = text
        messageLabel.isHidden = false
    }

    func dismiss() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        window?.orderOut(nil)
        onDismiss?()
    }

    func windowDidResignKey(_ notification: Notification) {
        if isVisible, !isShowingMenu { dismiss() }
    }
    func controlTextDidChange(_ obj: Notification) { reload(keepingSelection: false) }

    private func reload(keepingSelection: Bool) {
        let previousID = keepingSelection ? selectedEntry?.id : nil
        let previousRow = table.selectedRow
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredEntries = query.isEmpty ? allEntries : allEntries.filter {
            $0.payload.searchableText.localizedStandardContains(query) || $0.sourceName.localizedStandardContains(query)
        }
        table.reloadData()
        let isEmpty = filteredEntries.isEmpty
        emptyTitle.superview?.isHidden = !isEmpty
        emptyTitle.stringValue = query.isEmpty ? "你的下一次复制，会出现在这里" : "没有找到匹配的记录"
        emptySubtitle.stringValue = query.isEmpty ? "先用 ⌘C 复制，再用 ⌥V 找回。" : "试试其他关键词，或清空搜索。"
        if !isEmpty {
            let row = previousID.flatMap { id in filteredEntries.firstIndex { $0.id == id } }
                ?? (keepingSelection ? max(0, min(previousRow, filteredEntries.count - 1)) : 0)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    private var selectedEntry: HistoryEntry? {
        filteredEntries.indices.contains(table.selectedRow) ? filteredEntries[table.selectedRow] : nil
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredEntries.isEmpty else { return }
        let row = max(0, min(filteredEntries.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func acceptSelection() { if let selectedEntry { onPaste?(selectedEntry) } }
    private func deleteSelection() { if let selectedEntry { onDeleteEntry?(selectedEntry.id) } }
    @objc private func doubleClick() { useClickedRow(table.clickedRow) }

    func useClickedRow(_ row: Int) {
        guard filteredEntries.indices.contains(row) else { return }
        // Use the clicked item even when keyboard selection is empty or elsewhere.
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onPaste?(filteredEntries[row])
    }
    @objc private func requestPermission() { onPermission?() }
    @objc private func clearHistory() { onClear?() }
    @objc private func showMenu(_ sender: NSButton) {
        isShowingMenu = true
        defer { isShowingMenu = false }
        onMenu?(sender)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { filteredEntries.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .image = filteredEntries[row].payload { return 126 }
        return 78
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let cell = ClipCellView()
        cell.configure(entry)
        return cell
    }
}

private final class ClipRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 4), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        path.stroke()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 4), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class ClipCellView: NSTableCellView {
    private let preview = NSImageView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 7
        preview.layer?.masksToBounds = true
        title.font = .systemFont(ofSize: 13)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [title, preview, detail])
        row.orientation = .vertical
        row.spacing = 7
        row.alignment = .leading
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalTo: row.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 84),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalTo: row.widthAnchor),
            detail.widthAnchor.constraint(equalTo: row.widthAnchor)
        ])
        textField = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ entry: HistoryEntry) {
        var kind: String
        switch entry.payload {
        case .text(let text):
            preview.isHidden = true
            title.stringValue = String(text.prefix(500)).replacingOccurrences(of: "\n", with: "  ")
                .replacingOccurrences(of: "\r", with: " ")
            preview.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "文本")
            preview.contentTintColor = .secondaryLabelColor
            kind = "文本 · \(text.count) 字符"
            toolTip = String(text.prefix(2000))
        case .image(let data):
            title.isHidden = true
            let image = NSImage(data: data)
            preview.image = image
            title.stringValue = "图片"
            if let rep = image?.representations.first {
                kind = "图片 · \(rep.pixelsWide) × \(rep.pixelsHigh)"
            } else { kind = "图片" }
        case .files(let paths):
            preview.isHidden = true
            let urls = paths.compactMap(URL.init(string:))
            title.stringValue = urls.map(\.lastPathComponent).joined(separator: "、")
            preview.image = NSImage(systemSymbolName: paths.count > 1 ? "doc.on.doc" : "doc", accessibilityDescription: "文件")
            preview.contentTintColor = .secondaryLabelColor
            kind = "\(paths.count) 个文件"
            toolTip = urls.map(\.path).joined(separator: "\n")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        let source = entry.sourceName.isEmpty ? "" : " · \(entry.sourceName)"
        let age = Date().timeIntervalSince(entry.copiedAt)
        let time = age < 60 ? "刚刚" : formatter.localizedString(for: entry.copiedAt, relativeTo: Date())
        detail.stringValue = "\(kind)\(source) · \(time)"
        setAccessibilityLabel("\(title.stringValue)，\(detail.stringValue)")
    }
}
