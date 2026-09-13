import AppKit
import ClipboardCore

final class HistoryPanelController: NSWindowController, NSWindowDelegate, NSTableViewDataSource,
                                     NSTableViewDelegate, NSSearchFieldDelegate {
    private let table = HistoryTableView()
    let previews = HistoryPreviewCoordinator()
    var previewSettings = PreviewSettings() { didSet { previews.hover.cancel() } }
    private var previewSelectionID: UUID?
    private weak var previewResponder: NSResponder?
    private var scrollObserver: NSObjectProtocol?
    private let search = NSSearchField()
    private let countLabel = NSTextField(labelWithString: L10n.tr("0 条记录"))
    var shortcutName = "⌥V" { didSet { if search.stringValue.isEmpty { emptySubtitle.stringValue = L10n.tr("先用 ⌘C 复制，再用 {0} 找回。", String(describing: shortcutName)) } } }
    private let emptyTitle = NSTextField(wrappingLabelWithString: L10n.tr("你的下一次复制，会出现在这里"))
    private let emptySubtitle = NSTextField(wrappingLabelWithString: L10n.tr("先用 ⌘C 复制，再用 ⌥V 找回。"))
    private let permissionRow = NSStackView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let footerLabel = NSTextField(wrappingLabelWithString: L10n.tr("↑ ↓ 选择    ↩ 粘贴    esc 关闭"))
    private var allEntries: [HistoryEntry] = []
    private var filteredEntries: [HistoryEntry] = []
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var isShowingMenu = false
    private var draggedOrigin: NSPoint?
    var onOpenFavorites: (() -> Void)?
    var onFavorite: ((HistoryEntry) -> Void)?
    var isFavorite: ((HistoryEntry) -> Bool)?
    var onPaste: ((HistoryEntry) -> Void)?
    var onDeleteEntry: ((UUID) -> Void)?
    var onPermission: (() -> Void)?
    var onMenu: ((NSView) -> Void)?
    var onClear: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onOriginChanged: ((NSPoint) -> Void)?
    var onKeyboardRoute: ((String) -> Void)?
    var onCopyPreviewText: ((String) -> Bool)?

    init(origin: NSPoint? = nil) {
        draggedOrigin = origin
        let panel = KeyboardPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 490),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = L10n.tr("剪贴板历史")
        panel.setAccessibilityLabel(L10n.tr("剪贴板历史"))
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.onMove = { [weak self] in self?.moveSelection($0) }
        panel.onAccept = { [weak self] in self?.acceptSelection() }
        panel.onEscape = { [weak self] in self?.closePreviewOrDismiss() }
        panel.onPreview = { [weak self] in self?.toggleSelectedPreview() }
        panel.isPreviewOpen = { [weak self] in self?.previews.isPreviewing == true }
        panel.onDelete = { [weak self] in self?.deleteSelection() }
        panel.onKeyboardRoute = { [weak self] in self?.onKeyboardRoute?($0) }
        buildView(panel)
        configurePreviews()
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
        let title = NSTextField(labelWithString: L10n.tr("剪贴板"))
        title.font = .systemFont(ofSize: 18, weight: .bold)
        let titleColumn = NSStackView(views: [title, countLabel])
        titleColumn.orientation = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = 3
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        let clearButton = NSButton(title: L10n.tr("全部清空"), target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 12)
        clearButton.contentTintColor = .controlAccentColor
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearButton.imagePosition = .imageOnly
        clearButton.setAccessibilityLabel(L10n.tr("全部清空"))
        clearButton.toolTip = L10n.tr("全部清空")
        let menuButton = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: L10n.tr("更多选项"))!,
                                  target: self, action: #selector(showMenu(_:)))
        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.setAccessibilityLabel(L10n.tr("更多选项"))
        let favoritesButton = NSButton(title: L10n.tr("收藏"), image: NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, target: self, action: #selector(openFavorites))
        favoritesButton.isBordered = false
        favoritesButton.imagePosition = .imageOnly
        favoritesButton.setAccessibilityLabel(L10n.tr("打开收藏库"))
        favoritesButton.toolTip = L10n.tr("打开收藏库")
        // Keep the same compact geometry in every language. Full action names
        // remain available to VoiceOver and in tooltips and the menu.
        for button in [favoritesButton, clearButton, menuButton] {
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        }
        let headerContent = NSStackView(views: [icon, titleColumn, NSView(), favoritesButton, clearButton, menuButton])
        headerContent.spacing = 8
        headerContent.alignment = .centerY
        let header = DraggableHeaderView()
        header.toolTip = L10n.tr("拖动这里移动剪贴板")
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

        search.placeholderString = L10n.tr("搜索内容或来源应用")
        search.font = .systemFont(ofSize: 14)
        search.controlSize = .large
        search.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel(L10n.tr("搜索剪贴板历史"))
        (search.cell as? NSSearchFieldCell)?.searchButtonCell?.setAccessibilityLabel(L10n.tr("搜索"))
        (search.cell as? NSSearchFieldCell)?.cancelButtonCell?.setAccessibilityLabel(L10n.tr("取消"))
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
        table.setAccessibilityLabel(L10n.tr("剪贴板历史记录，使用上下键选择，回车粘贴"))
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
        for label in [emptyTitle, emptySubtitle] {
            label.alignment = .center
            label.maximumNumberOfLines = 3
        }
        let empty = NSStackView(views: [emptyTitle, emptySubtitle])
        empty.orientation = .vertical
        empty.spacing = 10
        empty.translatesAutoresizingMaskIntoConstraints = false
        listArea.addSubview(empty)
        for label in [emptyTitle, emptySubtitle] {
            label.widthAnchor.constraint(equalTo: listArea.widthAnchor, constant: -16).isActive = true
        }
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: listArea.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: listArea.centerYAnchor, constant: -16)
        ])

        let permissionText = NSTextField(wrappingLabelWithString: L10n.tr("允许辅助功能，即可回车粘贴到原应用"))
        permissionText.font = .systemFont(ofSize: 11)
        permissionText.textColor = .secondaryLabelColor
        permissionText.maximumNumberOfLines = 3
        permissionText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let permissionButton = NSButton(title: L10n.tr("去授权"), target: self, action: #selector(requestPermission))
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small
        permissionRow.setViews([permissionText, permissionButton], in: .leading)
        permissionRow.alignment = .centerY
        permissionRow.spacing = 8
        permissionRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        permissionText.widthAnchor.constraint(equalTo: permissionRow.widthAnchor,
            constant: -permissionButton.fittingSize.width - 8).isActive = true

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .systemOrange
        messageLabel.maximumNumberOfLines = 3
        messageLabel.isHidden = true
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.maximumNumberOfLines = 2
        let localLabel = NSTextField(labelWithString: L10n.tr("存于数据目录"))
        localLabel.font = .systemFont(ofSize: 10)
        localLabel.textColor = .tertiaryLabelColor
        localLabel.alignment = .right
        let footer = NSStackView(views: [footerLabel, localLabel])
        footer.orientation = .vertical
        footer.alignment = .width
        footer.spacing = 3
        footerLabel.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        localLabel.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true

        let divider = NSBox()
        divider.boxType = .separator
        let stack = NSStackView(views: [header, search, listArea, divider, permissionRow, messageLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        for view in [header, search, listArea, divider, permissionRow, messageLabel, footer] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            listArea.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }

    func present(entries: [HistoryEntry], hasPermission: Bool, paused: Bool) {
        if isVisible { dismiss() }
        allEntries = entries
        search.stringValue = ""
        messageLabel.isHidden = true
        updatePermission(hasPermission)
        countLabel.stringValue = L10n.tr("{0} 条记录{1}", String(describing: entries.count), String(describing: paused ? L10n.tr(" · 已暂停") : ""))
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
            if let self, !self.isShowingMenu, event.window !== self.window,
               !self.previews.contains(event.window) { self.dismiss() }
            return event
        }
    }

    func update(entries: [HistoryEntry], paused: Bool) {
        allEntries = entries
        countLabel.stringValue = L10n.tr("{0} 条记录{1}", String(describing: entries.count), String(describing: paused ? L10n.tr(" · 已暂停") : ""))
        reload(keepingSelection: true)
    }

    func updatePermission(_ allowed: Bool) {
        permissionRow.isHidden = allowed
        footerLabel.stringValue = L10n.tr("↑ ↓ 选择   空格预览   ↩ 粘贴   esc 关闭")
    }

    func showMessage(_ text: String) {
        messageLabel.stringValue = text
        messageLabel.isHidden = false
    }

    func dismiss() {
        previews.closeTransient(restoreSelection: false)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        window?.orderOut(nil)
        onDismiss?()
    }

    func windowDidResignKey(_ notification: Notification) {
        checkFamilyFocus()
    }
    func controlTextDidChange(_ obj: Notification) { reload(keepingSelection: false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === search, !textView.hasMarkedText(),
              (window as? KeyboardPanel)?.isComposing(for: NSApp.currentEvent) != true else { return false }
        if previews.isPreviewing {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { closePreviewOrDismiss(); return true }
            if [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)),
                #selector(NSResponder.moveUp(_:))].contains(commandSelector) { return true }
        }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onKeyboardRoute?(L10n.tr("搜索框命令：回车已接收"))
            if NSApp.currentEvent?.isARepeat != true { acceptSelection() }
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.cancelOperation(_:)): closePreviewOrDismiss()
        default: return false
        }
        return true
    }

    private func reload(keepingSelection: Bool) {
        previews.hover.cancel()
        let previousID = keepingSelection ? selectedEntry?.id : nil
        let previousRow = table.selectedRow
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredEntries = query.isEmpty ? allEntries : allEntries.filter {
            $0.payload.searchableText.localizedStandardContains(query) || $0.sourceName.localizedStandardContains(query)
        }
        table.reloadData()
        let isEmpty = filteredEntries.isEmpty
        emptyTitle.superview?.isHidden = !isEmpty
        emptyTitle.stringValue = query.isEmpty ? L10n.tr("你的下一次复制，会出现在这里") : L10n.tr("没有找到匹配的记录")
        emptySubtitle.stringValue = query.isEmpty ? L10n.tr("先用 ⌘C 复制，再用 {0} 找回。", String(describing: shortcutName)) : L10n.tr("试试其他关键词，或清空搜索。")
        if !isEmpty {
            let row = previousID.flatMap { id in filteredEntries.firstIndex { $0.id == id } }
                ?? (keepingSelection ? max(0, min(previousRow, filteredEntries.count - 1)) : 0)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        previews.reconcile(entries: filteredEntries)
    }

    private var selectedEntry: HistoryEntry? {
        filteredEntries.indices.contains(table.selectedRow) ? filteredEntries[table.selectedRow] : nil
    }

    private func moveSelection(_ delta: Int) {
        previews.hover.cancel()
        guard !filteredEntries.isEmpty else { return }
        let row = max(0, min(filteredEntries.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func acceptSelection() {
        previews.hover.cancel()
        guard !previews.isPreviewing else { return }
        if let selectedEntry { onPaste?(selectedEntry) }
    }
    private func deleteSelection() {
        previews.hover.cancel()
        guard !previews.isPreviewing else { return }
        if let selectedEntry { onDeleteEntry?(selectedEntry.id) }
    }
    @objc private func doubleClick() { useClickedRow(table.clickedRow) }

    func useClickedRow(_ row: Int) {
        guard filteredEntries.indices.contains(row) else { return }
        previews.closeTransient(restoreSelection: false)
        // Use the clicked item even when keyboard selection is empty or elsewhere.
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onPaste?(filteredEntries[row])
    }
    @objc private func requestPermission() { onPermission?() }
    @objc private func openFavorites() { onOpenFavorites?() }
    @objc private func clearHistory() { onClear?() }
    @objc private func showMenu(_ sender: NSButton) {
        previews.hover.cancel()
        isShowingMenu = true
        defer { isShowingMenu = false }
        onMenu?(sender)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { filteredEntries.count }

    private func configurePreviews() {
        previews.onCopyText = { [weak self] in self?.onCopyPreviewText?($0) == true }
        previews.onRestoreSelection = { [weak self] in self?.restorePreviewSelection() }
        previews.onFamilyResignKey = { [weak self] in self?.checkFamilyFocus() }
        table.onHoverRow = { [weak self] row in self?.scheduleHover(row: row) }
        table.onCancelHover = { [weak self] in self?.previews.hover.cancel() }
        table.contextMenuForRow = { [weak self] row in self?.previewMenu(row: row) }
        if let clip = table.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: clip, queue: .main) { [weak self] _ in self?.previews.hover.cancel() }
        }
    }

    private func scheduleHover(row: Int) {
        guard previewSettings.hoverEnabled, isVisible, !isShowingMenu,
              filteredEntries.indices.contains(row) else { previews.hover.cancel(); return }
        let id = filteredEntries[row].id
        if previews.transient?.entryID == id { return }
        previews.hover.schedule(id: id, delay: previewSettings.hoverDelay) { [weak self] in
            guard let self, self.isVisible, !self.isShowingMenu,
                  let row = self.filteredEntries.firstIndex(where: { $0.id == id }),
                  self.table.visibleRect.intersects(self.table.rect(ofRow: row)) else { return }
            self.showPreview(row: row, takeFocus: false)
        }
    }

    func showPreview(row: Int, takeFocus: Bool) {
        guard filteredEntries.indices.contains(row), let window else { return }
        if !previews.isPreviewing {
            previewSelectionID = selectedEntry?.id
            previewResponder = window.firstResponder
        }
        let rect = table.convert(table.rect(ofRow: row), to: nil)
        previews.show(entry: filteredEntries[row], anchor: window.convertToScreen(rect), parent: window, takeFocus: takeFocus)
    }

    private func toggleSelectedPreview() {
        previews.hover.cancel()
        if previews.isPreviewing { previews.closeTransient(restoreSelection: true) }
        else { showPreview(row: table.selectedRow, takeFocus: true) }
    }

    private func closePreviewOrDismiss() {
        if previews.isPreviewing { previews.closeTransient(restoreSelection: true) }
        else { dismiss() }
    }

    private func restorePreviewSelection() {
        guard isVisible else { return }
        if let id = previewSelectionID, let row = filteredEntries.firstIndex(where: { $0.id == id }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        window?.makeKey()
        if previewResponder is NSTextView { window?.makeFirstResponder(search) }
        else { window?.makeFirstResponder(previewResponder ?? table) }
    }

    private func checkFamilyFocus() {
        // Key-window notifications arrive before the replacement is established.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isShowingMenu else { return }
            if NSApp.keyWindow !== self.window, !self.previews.contains(NSApp.keyWindow) { self.dismiss() }
        }
    }

    private func previewMenu(row: Int) -> NSMenu? {
        guard filteredEntries.indices.contains(row) else { return nil }
        let entry = filteredEntries[row]
        let menu = NSMenu()
        menu.delegate = self
        let title: String
        if case .image = entry.payload { title = L10n.tr("查看原图") } else { title = L10n.tr("预览完整内容") }
        let item = menu.addItem(withTitle: title, action: #selector(previewFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = entry.id
        if onFavorite != nil {
            menu.addItem(.separator())
            let favorite = menu.addItem(withTitle: isFavorite?(entry) == true ? L10n.tr("取消收藏") : L10n.tr("收藏到未分类"), action: #selector(toggleFavoriteFromMenu(_:)), keyEquivalent: "")
            favorite.target = self;favorite.representedObject = entry.id
        }
        return menu
    }

    @objc private func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let entry = filteredEntries.first(where: { $0.id == id }) else { return }
        onFavorite?(entry)
    }

    @objc private func previewFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let row = filteredEntries.firstIndex(where: { $0.id == id }) else { return }
        showPreview(row: row, takeFocus: true)
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .image = filteredEntries[row].payload { return 126 }
        return 78
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let cell = ClipCellView()
        cell.configure(entry)
        if onFavorite != nil { cell.configureFavorite(isFavorite?(entry) == true) { [weak self] in self?.onFavorite?(entry) } }
        return cell
    }
}

extension HistoryPanelController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isShowingMenu = true
        previews.hover.cancel()
    }
    func menuDidClose(_ menu: NSMenu) { isShowingMenu = false }
}
