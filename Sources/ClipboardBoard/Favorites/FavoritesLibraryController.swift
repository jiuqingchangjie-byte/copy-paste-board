import AppKit
import ClipboardCore

/// Browsing and selection actions for the independent, paged favorites library.
final class FavoritesLibraryController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private(set) var content = FavoritesLibraryView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
    let previews = HistoryPreviewCoordinator()
    private var repository: FavoritesRepository?
    private var folders: [FavoriteFolder] = []
    private var items: [FavoriteSummary] = []
    private var scope: FavoriteScope = .all
    private var offset = 0
    private var total = 0
    private var allCount = 0
    private var unfiledCount = 0
    private var reloading = false
    private(set) var isMutating = false
    private let mutationQueue = DispatchQueue(label:"ClipboardBoard.favorites",qos:.userInitiated)
    var onCopy: ((HistoryEntry) -> Bool)?
    var onChange: (() -> Void)?
    var isVisible: Bool { window?.isVisible == true }

    init() {
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1000,height:600), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L10n.tr("收藏库")
        window.minSize = NSSize(width: 1000, height: 500)
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        configureContent()
    }

    private func configureContent() {
        content.folders.dataSource = self; content.folders.delegate = self
        content.entries.dataSource = self; content.entries.delegate = self
        content.search.delegate = self
        content.entries.target = self; content.entries.doubleAction = #selector(previewClicked)
        content.entries.onPreview = { [weak self] in self?.showPreview() }
        content.entries.onRemove = { [weak self] in self?.removeSelected() }
        content.entries.onCopy = { [weak self] in self?.copySelected() }
        for (button,action) in [(content.newFolder,#selector(newFolder)),(content.folderMenu,#selector(showFolderMenu)),
            (content.preview,#selector(showPreview)),(content.copy,#selector(copySelected)),(content.move,#selector(showMoveMenu)),
            (content.remove,#selector(removeSelected)),(content.clear,#selector(clearLibrary)),
            (content.previous,#selector(previousPage)),(content.next,#selector(nextPage))] {
            button.target = self; button.action = action
        }
        previews.onCopyText = { [weak self] text in self?.onCopy?(HistoryEntry(payload: .text(text),sourceName: L10n.tr("收藏预览"))) == true }
        previews.onRestoreSelection = { [weak self] in
            guard let self, self.isVisible else { return }
            self.window?.makeKeyAndOrderFront(nil); self.window?.makeFirstResponder(self.content.entries)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshLanguage() {
        guard !isMutating else { return }
        let query = content.search.stringValue
        let selected = selectedIDs
        previews.closeAll()
        content = FavoritesLibraryView(frame: content.frame)
        window?.title = L10n.tr("收藏库")
        window?.contentView = content
        configureContent()
        content.search.stringValue = query
        reload()
        content.entries.selectRowIndexes(IndexSet(items.indices.filter { selected.contains(items[$0].id) }), byExtendingSelection: false)
    }

    func setRepository(_ repository: FavoritesRepository?, message: String? = nil) {
        self.repository = repository
        previews.closeAll()
        reload()
        if let message { showMessage(message, error: repository == nil) }
    }
    func present() {
        reload()
        if !isVisible { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(content.search)
    }
    func windowWillClose(_ notification: Notification) { previews.closeTransient(restoreSelection: false) }
    func finishPendingChanges() { mutationQueue.sync {} }
    private var selectedIDs: Set<UUID> { Set(content.entries.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil }) }

    func reload() {
        guard !reloading, !isMutating else { return }
        reloading = true; defer { reloading = false }
        let selected = selectedIDs
        do {
            if let repository {
                folders = try repository.folders()
                if case .folder(let id) = scope, !folders.contains(where: { $0.id == id }) { scope = .unfiled; offset = 0 }
                allCount = try repository.page(limit: 1).total
                unfiledCount = try repository.page(scope: .unfiled, limit: 1).total
                var page = try repository.page(scope: scope, query: content.search.stringValue, offset: offset)
                if offset >= page.total, offset > 0 { offset = max(0, ((max(page.total,1)-1)/100)*100); page = try repository.page(scope: scope,query: content.search.stringValue,offset: offset) }
                items = page.items; total = page.total
            } else { folders = []; items = []; total = 0; allCount = 0; unfiledCount = 0; scope = .all; offset = 0 }
            content.folders.reloadData()
            let folderRow: Int
            switch scope {
            case .all: folderRow = 0; content.heading.stringValue = L10n.tr("全部收藏")
            case .unfiled: folderRow = 1; content.heading.stringValue = L10n.tr("未分类")
            case .folder(let id):
                folderRow = 2 + (folders.firstIndex(where: { $0.id == id }) ?? 0)
                content.heading.stringValue = folders.first(where: { $0.id == id })?.name ?? L10n.tr("未分类")
            }
            content.folders.selectRowIndexes(IndexSet(integer: folderRow), byExtendingSelection: false)
            content.entries.reloadData()
            content.entries.selectRowIndexes(IndexSet(items.indices.filter { selected.contains(items[$0].id) }), byExtendingSelection: false)
            content.pageLabel.stringValue = total == 0 ? L10n.tr("暂无收藏") : L10n.tr("共 {0} 条 · {1}–{2}", String(describing: total), String(describing: offset+1), String(describing: offset+items.count))
            showMessage(total == 0 ? L10n.tr("在历史条目上点击星标或右键收藏，内容会独立保存在这里。") : L10n.tr("⌘ / Shift 多选当前页 · 双击查看完整内容 · 复制后可到目标应用粘贴"), error: false)
        } catch { showMessage(error.localizedDescription,error: true) }
        updateActions()
    }
    private func updateActions() {
        let count = selectedIDs.count
        let available = repository != nil && !isMutating
        content.search.isEnabled = available
        content.folders.isEnabled = available
        content.entries.isEnabled = available
        content.preview.isEnabled = available && count == 1
        content.copy.isEnabled = available && count == 1
        content.move.isEnabled = available && count > 0
        content.remove.isEnabled = available && count > 0
        content.remove.title = count > 1 ? L10n.tr("取消收藏（{0}）", String(describing: count)) : L10n.tr("取消收藏")
        content.clear.isEnabled = available && allCount > 0
        content.newFolder.isEnabled = available
        content.folderMenu.isEnabled = available
        content.previous.isEnabled = available && offset > 0
        content.next.isEnabled = available && offset + items.count < total
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === content.folders ? folders.count + 2 : items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableView === content.folders {
            if row == 0 { text = L10n.tr("★ 全部收藏（{0}）", String(describing: allCount)) }
            else if row == 1 { text = L10n.tr("▱ 未分类（{0}）", String(describing: unfiledCount)) }
            else { text = "▸ \(folders[row-2].name)（\(folders[row-2].count)）" }
        } else {
            let item = items[row]
            switch tableColumn?.identifier.rawValue {
            case "kind": text = L10n.tr(item.kind)
            case "source": text = L10n.sourceName(item.source)
            default: text = item.kind == "图片" ? L10n.tr("图片收藏") : item.title
            }
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13)
        label.toolTip = text
        if tableView === content.entries, tableColumn?.identifier.rawValue == "title" {
            let image: NSImage?
            if let data = items[row].thumbnail { image = NSImage(data:data) }
            else { image = NSImage(systemSymbolName: items[row].kind == "图片" ? "photo" : items[row].kind == "文件" ? "doc" : "text.alignleft",accessibilityDescription:nil) }
            let icon = NSImageView();icon.image = image;icon.imageScaling = .scaleProportionallyUpOrDown
            if items[row].thumbnail == nil { icon.imageScaling = .scaleProportionallyDown }
            icon.widthAnchor.constraint(equalToConstant:48).isActive = true;icon.heightAnchor.constraint(equalToConstant:32).isActive = true
            let stack = NSStackView(views:[icon,label]);stack.spacing = 8
            return stack
        }
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, !isMutating else { return }
        if notification.object as? NSTableView === content.folders {
            let row = content.folders.selectedRow
            guard row >= 0 else { return }
            scope = row == 0 ? .all : row == 1 ? .unfiled : .folder(folders[row-2].id)
            offset = 0; content.search.stringValue = ""; previews.closeTransient(restoreSelection: false); reload()
        } else { updateActions() }
    }
    func controlTextDidChange(_ obj: Notification) { offset = 0; previews.closeTransient(restoreSelection: false); reload() }
    private func mutate<T>(_ body: @escaping (FavoritesRepository) throws -> T, after: @escaping (T) -> Void = { _ in }) {
        guard let repository, !isMutating else { return }
        isMutating = true;updateActions();showMessage(L10n.tr("正在保存收藏…"),error:false)
        mutationQueue.async { [weak self] in
            let result = Result { try body(repository) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMutating = false
                guard self.repository === repository else { self.updateActions();return }
                switch result {
                case .success(let value): after(value);self.reload();self.onChange?()
                case .failure(let error): self.showMessage(error.localizedDescription,error:true);self.updateActions()
                }
            }
        }
    }
    private func showMessage(_ text: String, error: Bool) { content.status.stringValue = text; content.status.textColor = error ? .systemRed : .secondaryLabelColor }
    private func confirm(_ title: String, detail: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: action); alert.addButton(withTitle: L10n.tr("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func folderName(title: String, initial: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = L10n.tr("名称 1–60 个字符。同一收藏库内不能重名。")
        let field = NSTextField(frame: NSRect(x:0,y:0,width:280,height:26)); field.stringValue = initial
        field.setAccessibilityLabel(L10n.tr("收藏文件夹名称"))
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.addButton(withTitle: L10n.tr("保存")); alert.addButton(withTitle: L10n.tr("取消"))
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    @objc private func newFolder() { if let name = folderName(title: L10n.tr("新建收藏文件夹")) { mutate({ try $0.createFolder(name:name) },after:{ [weak self] id in self?.scope = .folder(id); self?.offset = 0 }) } }
    @objc private func renameFolder() {
        guard case .folder(let id) = scope, let name = folderName(title: L10n.tr("重命名文件夹"), initial: content.heading.stringValue) else { return }
        mutate { try $0.renameFolder(id: id,name: name) }
    }
    @objc private func deleteFolder() {
        guard case .folder(let id) = scope, confirm(L10n.tr("删除“{0}”文件夹？", String(describing: content.heading.stringValue)), detail: L10n.tr("收藏内容不会删除，会移至“未分类”。"), action: L10n.tr("删除文件夹")) else { return }
        mutate({ try $0.deleteFolder(id: id) },after:{ [weak self] _ in self?.scope = .unfiled;self?.offset = 0 })
    }
    @objc private func showFolderMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false
        let isFolder: Bool; if case .folder = scope { isFolder = true } else { isFolder = false }
        for (title,action) in [(L10n.tr("重命名文件夹…"),#selector(renameFolder)),(L10n.tr("删除文件夹…"),#selector(deleteFolder)),(L10n.tr("清空当前目录…"),#selector(clearFolder))] {
            let item = menu.addItem(withTitle:title,action:action,keyEquivalent:"");item.target = self
            item.isEnabled = action == #selector(clearFolder) ? scope != .all && (scope == .unfiled ? unfiledCount : folders.first(where: { .folder($0.id) == scope })?.count ?? 0) > 0 : isFolder
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:content.folderMenu.bounds.maxY),in:content.folderMenu)
    }
    @objc private func showMoveMenu() {
        let menu = NSMenu()
        let unfiled = menu.addItem(withTitle:L10n.tr("未分类"),action:#selector(moveToFolder(_:)),keyEquivalent:""); unfiled.target = self
        for folder in folders { let item = menu.addItem(withTitle:folder.name,action:#selector(moveToFolder(_:)),keyEquivalent:"");item.target = self;item.representedObject = folder.id }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:content.move.bounds.maxY),in:content.move)
    }
    @objc private func moveToFolder(_ sender: NSMenuItem) { let ids = selectedIDs; let destination = sender.representedObject as? UUID; mutate { try $0.move(ids:ids,to:destination) } }
    @objc private func removeSelected() {
        let ids = selectedIDs; guard !ids.isEmpty else { return }
        guard confirm(L10n.tr("取消收藏这 {0} 条内容？", String(describing: ids.count)),detail:L10n.tr("普通历史和系统剪贴板不受影响。此操作不能撤销。"),action:L10n.tr("取消收藏")) else { return }
        previews.closeTransient(restoreSelection:false)
        mutate { try $0.remove(ids:ids) }
    }
    @objc private func clearLibrary() {
        guard allCount > 0, confirm(L10n.tr("清空全部 {0} 条收藏？", String(describing: allCount)),detail:L10n.tr("包含所有目录，不受当前搜索条件限制。文件夹保留，普通历史和系统剪贴板不受影响。此操作不能撤销。"),action:L10n.tr("清空收藏库")) else { return }
        previews.closeAll(); mutate { try $0.clear() }
    }
    @objc private func clearFolder() {
        guard scope != .all, confirm(L10n.tr("清空“{0}”？", String(describing: content.heading.stringValue)),detail:L10n.tr("删除此目录内全部收藏（含搜索未显示的内容），不影响其他目录或普通历史。"),action:L10n.tr("清空目录")) else { return }
        previews.closeTransient(restoreSelection:false);let currentScope = scope;mutate { try $0.clear(scope:currentScope) }
    }
    @objc private func copySelected() {
        guard selectedIDs.count == 1, let id = selectedIDs.first, let repository else { return }
        do { if let entry = try repository.entry(id:id) { showMessage(onCopy?(entry) == true ? L10n.tr("已复制到剪贴板并加入普通历史") : L10n.tr("复制失败，请检查文件是否仍存在或内容是否过大。"),error:false) } }
        catch { showMessage(error.localizedDescription,error:true) }
    }
    @objc private func previewClicked() {
        let row = content.entries.clickedRow;guard items.indices.contains(row) else { return }
        content.entries.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);showPreview()
    }
    @objc private func showPreview() {
        guard selectedIDs.count == 1, let id = selectedIDs.first, let repository, let window else { return }
        do {
            if let entry = try repository.entry(id:id) {
                let rect = content.entries.convert(content.entries.rect(ofRow:content.entries.selectedRow),to:nil)
                previews.show(entry:entry,anchor:window.convertToScreen(rect),parent:window,takeFocus:true)
            }
        } catch { showMessage(error.localizedDescription,error:true) }
    }
    @objc private func previousPage() { offset = max(0,offset-100);reload() }
    @objc private func nextPage() { offset += 100;reload() }
}
