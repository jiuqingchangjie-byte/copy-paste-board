import AppKit
import ApplicationServices
import ClipboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PasteboardMonitor()
    private lazy var previewCopy = PreviewCopyService(monitor: monitor)
    private let previewPreferences = PreviewPreferencesController()
    private let hotKey = GlobalHotKey()
    private lazy var shortcutPreferences = ShortcutPreferencesController()
    private var shortcutName: String { (hotKey.activeShortcut ?? settings.shortcut).displayName }
    private var shortcutError: String?
    private let pasteService = PasteService()
    private let launchAtLogin = LaunchAtLoginService()
    private var panel: HistoryPanelController!
    private var statusItem: NSStatusItem!
    private var targetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var dismissingForPaste = false
    private var history = History()
    private var settings = AppSettings()
    private var maxCount: Int { settings.maxHistoryCount }
    private var dataStore = AppDataStore(applicationURL: Bundle.main.bundleURL)
    private let storageLocation = StorageLocation(applicationURL: Bundle.main.bundleURL)
    private lazy var storagePreferences = StoragePreferencesController()
    private lazy var favorites = FavoritesCoordinator()
    private var relocatingStorage = false
    private var storage: HistoryStorage { dataStore.history }
    private var storageReady = false
    private let storageQueue = DispatchQueue(label: "ClipboardBoard.storage", qos: .utility)
    private var saveError: String?
    private var pendingRemovals = Set<UUID>()
    private var clearedWhileUnavailable = false
    private var storageBusy = false
    private var storageRevision = 0
    private var permissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var hotKeyRegistered = false
    private var lastPasteProgress = L10n.tr("尚未使用历史记录")
    private var lastKeyboardRoute = L10n.tr("尚未接收回车")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep only one monitor/hotkey owner, even if launched twice from the command line.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
           }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApplication = front }
        L10n.language = .preferred(from: Locale.preferredLanguages)
        loadStoredData()
        L10n.language = settings.language
        lastPasteProgress = L10n.tr("尚未使用历史记录")
        lastKeyboardRoute = L10n.tr("尚未接收回车")
        configureEditMenu()
        configureHistoryPanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: L10n.tr("剪贴板"))
            button.image?.isTemplate = true
            button.toolTip = L10n.tr("剪贴板 · {0}", String(describing: shortcutName))
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            if self.shortcutPreferences.isVisible {
                self.shortcutPreferences.receiveRegisteredShortcut(self.hotKey.activeShortcut ?? self.settings.shortcut)
            } else { self.togglePanel() }
        }
        registerConfiguredShortcut()
        monitor.onCapture = { [weak self] payload, source in
            guard let self else { return }
            if self.history.insert(HistoryEntry(payload: payload, sourceName: source)) { self.historyChanged() }
        }
        monitor.start()
        RuntimeIdentity.write()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.panel.updatePermission(self.pasteService.hasPermission)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.lastExternalApplication = app
            if self.panel.isVisible, app.processIdentifier != self.targetApplication?.processIdentifier {
                self.panel.dismiss()
            }
        }
        if !settings.hasLaunched || !hotKeyRegistered || !storageReady {
            var next = settings
            next.hasLaunched = true
            do { try saveSettings(next) }
            catch { if saveError == nil { saveError = L10n.tr("暂时无法保存，记录仍可使用。请打开“数据与恢复”重试。") } }
            showPanel()
        }
    }

    private func configureHistoryPanel() {
        let origin = settings.panelOrigin.map { NSPoint(x: $0[0], y: $0[1]) }
        panel = HistoryPanelController(origin: origin)
        panel.previewSettings = settings.preview
        favorites.onCopy = { [weak self] entry in
            self?.previewCopy.copy(entry.payload, sourceName: L10n.tr("收藏库")) == true
        }
        favorites.onMessage = { [weak self] in self?.panel.showMessage($0) }
        favorites.onChanged = { [weak self] in
            guard let self else { return }
            self.panel.update(entries:self.history.entries,paused:self.monitor.isPaused)
        }
        if favorites.repository == nil { favorites.open(store:dataStore,available:storageReady) }
        panel.onOpenFavorites = { [weak self] in self?.openFavorites() }
        panel.isFavorite = { [weak self] in self?.favorites.isFavorite($0) == true }
        panel.onFavorite = { [weak self] entry in
            guard let self else { return }
            guard !self.relocatingStorage else { self.panel.showMessage(L10n.tr("正在迁移存储，请稍后收藏。"));return }
            self.favorites.toggle(entry)
        }
        storagePreferences.onMove = { [weak self] destination, completion in
            self?.relocateStorage(to:destination,completion:completion)
        }
        previewCopy.onCopied = { [weak self] entry in
            guard let self else { return }
            if self.history.insert(entry) { self.historyChanged() }
        }
        panel.onCopyPreviewText = { [weak self] in self?.previewCopy.copy($0) == true }
        pasteService.onProgress = { [weak self] in self?.lastPasteProgress = $0 }
        panel.onKeyboardRoute = { [weak self] in self?.lastKeyboardRoute = $0 }
        panel.onOriginChanged = { [weak self] origin in
            guard let self else { return }
            var next = self.settings
            next.panelOrigin = [Double(origin.x), Double(origin.y)]
            do { try self.saveSettings(next) }
            catch { self.panel.showMessage(L10n.tr("位置保存失败，请检查安装目录的写入权限。")) }
        }
        panel.onPaste = { [weak self] in self?.use($0) }
        panel.onDismiss = { [weak self] in
            guard let self, !self.dismissingForPaste else { return }
            self.pasteService.cancel()
        }
        panel.onDeleteEntry = { [weak self] id in
            guard let self else { return }
            if !self.storageReady { self.pendingRemovals.insert(id) }
            self.history.remove(id: id)
            self.historyChanged()
        }
        panel.onClear = { [weak self] in self?.clearHistory() }
        panel.onPermission = { [weak self] in
            self?.panel.dismiss()
            self?.pasteService.openPermissionSettings()
        }
        panel.onMenu = { [weak self] view in
            guard let self else { return }
            self.makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY), in: view)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.previews.closeAll()
        permissionTimer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        // Finish pending atomic saves before quitting, including a pending clear.
        storageQueue.sync {}
        favorites.shutdown()
        if storageReady, let store = try? storageLocation.resolve() {
            try? store.history.save(history.entries)
            try? store.saveSettings(settings)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-activation must not rebuild an already open list or steal focus
        // from a preview/sheet; that would invalidate selection and controls.
        if let modal = NSApp.modalWindow { modal.makeKeyAndOrderFront(nil); return false }
        if let current = NSApp.keyWindow, current.isVisible { current.makeKeyAndOrderFront(nil); return false }
        if shortcutPreferences.isVisible {
            shortcutPreferences.window?.makeKeyAndOrderFront(nil)
            return false
        }
        if storagePreferences.isVisible { storagePreferences.window?.makeKeyAndOrderFront(nil);return false }
        if favorites.library.isVisible { favorites.library.window?.makeKeyAndOrderFront(nil);return false }
        if panel.isVisible { panel.window?.makeKeyAndOrderFront(nil);return false }
        showPanel()
        return false
    }

    private func historyChanged() {
        panel.update(entries: history.entries, paused: monitor.isPaused)
        if relocatingStorage { panel.showMessage(L10n.tr("迁移期间新复制暂存于内存，完成后保存。"));return }
        guard storageReady else {
            panel.showMessage(L10n.tr("记录暂存于本次运行。打开“数据与恢复”可重试保存。"))
            return
        }
        let entries = history.entries
        let storage = storage
        storageRevision += 1
        let revision = storageRevision
        storageQueue.async { [weak self] in
            do {
                try storage.save(entries)
                DispatchQueue.main.async {
                    guard let self, self.storageRevision == revision else { return }
                    self.saveError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.storageRevision == revision else { return }
                    self.saveError = L10n.tr("保存暂未完成，记录仍在。打开“数据与恢复”重试。")
                    self.panel.showMessage(self.saveError ?? "")
                }
            }
        }
    }

    private func loadStoredData() {
        storageReady = false
        do {
            dataStore = AppDataStore(directoryURL:try storageLocation.selectedDirectory())
            _ = try storageLocation.resolve()
        } catch { saveError = error.localizedDescription;return }
        let legacyLimit = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        let legacySettings = AppSettings(
            maxHistoryCount: legacyLimit > 0 ? legacyLimit : 10,
            panelOrigin: UserDefaults.standard.array(forKey: "historyPanelOrigin") as? [Double],
            hasLaunched: UserDefaults.standard.bool(forKey: "hasLaunched"), language: .chinese)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = support.appendingPathComponent("ClipboardBoard/history.json")
        do {
            let hasLegacyData = FileManager.default.fileExists(atPath: legacyURL.path)
                || ["maxHistoryCount", "historyPanelOrigin", "hasLaunched"].contains { UserDefaults.standard.object(forKey: $0) != nil }
            if !storageLocation.isCustom {
                try dataStore.migrateLegacyIfNeeded(historyURL: legacyURL, settings: hasLegacyData ? legacySettings : AppSettings())
            }
            settings = try dataStore.loadSettings()
            L10n.language = settings.language
            let storedEntries = try storage.load()
            history = History(entries: storedEntries, maxCount: maxCount)
            if history.entries != storedEntries { try storage.save(history.entries) }
            // Persist the normalized setting too, including an old limit above 50.
            try dataStore.saveSettings(settings)
            storageReady = true
            saveError = nil
            for key in ["maxHistoryCount", "historyPanelOrigin", "hasLaunched"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        } catch {
            // Reading the old file is safe; never overwrite it after a failed migration.
            settings = (try? dataStore.loadSettings()) ?? legacySettings
            L10n.language = settings.language
            let source = storageLocation.isCustom || FileManager.default.fileExists(atPath: storage.fileURL.path)
                ? storage : HistoryStorage(fileURL: legacyURL)
            history = History(entries: (try? source.load()) ?? [], maxCount: maxCount)
            if error is DataFormatError {
                saveError = L10n.tr("数据由更新版本创建。原文件已保留，请使用更新版本打开。")
            } else {
                saveError = L10n.tr("部分数据暂时无法读取，原文件已保留。打开“数据与恢复”处理。")
            }
        }
    }

    private var legacyHistoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardBoard/history.json")
    }

    /// Called on the main thread, after pending writes finish. If startup could
    /// not read the disk, merge recovered history with this session's copies,
    /// respecting deletions/clear made while persistence was unavailable.
    private func retryStorage() {
        guard !storageBusy else { return }
        storageBusy = true
        let interfaceLanguage = L10n.language
        defer {
            storageBusy = false
            if interfaceLanguage != settings.language { refreshLanguageInterface() }
        }
        storageQueue.sync {}
        storageRevision += 1
        let current = history.entries
        if !storageReady {
            loadStoredData()
            panel.previewSettings = settings.preview
            registerConfiguredShortcut()
            history = History.recovering(history.entries, keeping: current, removedIDs: pendingRemovals,
                                         wasCleared: clearedWhileUnavailable, maxCount: maxCount)
        }
        do {
            guard storageReady else { panel.update(entries: history.entries, paused: monitor.isPaused); return }
            try dataStore.saveSettings(settings)
            try storage.save(history.entries)
            pendingRemovals.removeAll()
            clearedWhileUnavailable = false
            saveError = nil
            panel.update(entries: history.entries, paused: monitor.isPaused)
            panel.showMessage(L10n.tr("已保存，可以继续使用。"))
            favorites.open(store:dataStore,available:true)
        } catch {
            saveError = L10n.tr("暂时无法保存，记录仍在本次运行中。请确认磁盘空间和目录写入权限后重试。")
        }
    }

    private func saveSettings(_ next: AppSettings) throws {
        guard storageReady, !relocatingStorage else {
            throw NSError(domain: "ClipboardBoard.Storage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.tr("数据目录不可用，请将应用放在可写目录后重启。")])
        }
        try dataStore.saveSettings(next)
        settings = next
    }

    private func configureEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = appMenu.addItem(withTitle: L10n.tr("退出剪贴板"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: L10n.tr("编辑"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: L10n.tr("编辑"))
        edit.addItem(withTitle: L10n.tr("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.tr("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.tr("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.tr("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem.button {
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else { togglePanel() }
    }

    @objc private func togglePanel() {
        if shortcutPreferences.isVisible { shortcutPreferences.window?.makeKeyAndOrderFront(nil); return }
        if panel.isVisible { panel.dismiss() }
        else { showPanel() }
    }

    private func showPanel() {
        pasteService.cancel()
        monitor.poll() // Include a copy that happened just before the shortcut.
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApplication = front
            lastExternalApplication = front
        } else {
            targetApplication = lastExternalApplication
        }
        pasteService.captureTarget(targetApplication)
        panel.present(entries: history.entries, hasPermission: pasteService.hasPermission, paused: monitor.isPaused)
        if !hotKeyRegistered { panel.showMessage(shortcutError ?? L10n.tr("{0} 未注册，可从菜单栏重新设置快捷键。", String(describing: shortcutName))) }
        else if let saveError { panel.showMessage(saveError) }
    }

    private func use(_ entry: HistoryEntry) {
        pasteService.paste(into: targetApplication, prepareClipboard: { [weak self] in
            self?.monitor.write(entry.payload) ?? false
        }, beforeActivation: { [weak self] in
            guard let self else { return }
            self.dismissingForPaste = true
            self.panel.dismiss()
            self.dismissingForPaste = false
        }) { [weak self] outcome in
            guard let self else { return }
            self.lastPasteProgress = outcome.localizedDescription
            switch outcome {
            case .eventPosted: break
            case .permissionRequired:
                if !self.panel.isVisible { self.showPanel() }
                self.panel.showMessage(L10n.tr("未粘贴：请点击“去授权”，允许辅助功能后再使用。"))
            case .targetUnavailable:
                self.showPanel()
                self.panel.showMessage(L10n.tr("未粘贴：请先点击目标输入框，再按 {0} 选择记录。", String(describing: self.shortcutName)))
            case .focusChanged:
                break // Respect a deliberate switch to another application.
            case .keysStillPressed:
                if !self.panel.isVisible { self.showPanel() }
                self.panel.showMessage(L10n.tr("请松开 ⌥、⌘ 和回车键，再按一次回车粘贴。"))
            case .clipboardChanged:
                self.showPanel()
                self.panel.showMessage(L10n.tr("等待粘贴时发生了新的复制，请重新选择历史记录。"))
            case .clipboardWriteFailed:
                self.panel.showMessage(L10n.tr("无法使用这条记录：文件可能已移动，或内容已损坏。"))
            case .deliveryUncertain:
                self.showPanel()
                self.panel.showMessage(L10n.tr("目标应用未及时确认，请先检查输入框，避免重复粘贴。"))
            }
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        _ = item(L10n.tr("打开历史记录    {0}", String(describing: shortcutName)), #selector(togglePanel))
        _ = item(L10n.tr("打开收藏库"), #selector(openFavorites))
        menu.addItem(makeLanguageMenu())
        _ = item(L10n.tr("存储位置…"), #selector(openStoragePreferences))
        _ = item(L10n.tr("自定义快捷键…（{0}）", String(describing: shortcutName)), #selector(configureShortcut))
        _ = item(L10n.tr("历史记录上限：{0} 条…", String(describing: maxCount)), #selector(configureLimit))
        _ = item(L10n.tr("完整预览选项…"), #selector(configurePreview))
        let login = NSMenuItem(title: L10n.tr("登录时自动启动"), action: nil, keyEquivalent: "")
        login.view = LaunchAtLoginMenuView(service: launchAtLogin) { [weak self, weak menu] in
            menu?.cancelTracking()
            self?.openLoginSettings()
        }
        menu.addItem(login)
        _ = item(monitor.isPaused ? L10n.tr("继续记录") : L10n.tr("暂停记录"), #selector(togglePause))
        menu.addItem(.separator())
        let clear = item(L10n.tr("清空全部历史"), #selector(clearHistory))
        clear.isEnabled = !history.entries.isEmpty
        _ = item(L10n.tr("辅助功能权限…"), #selector(openPermissions))
        _ = item(L10n.tr("粘贴诊断…"), #selector(showPasteDiagnostics))
        _ = item(L10n.tr("打开数据目录"), #selector(openDataDirectory))
        _ = item(saveError == nil ? L10n.tr("数据与恢复…") : L10n.tr("数据与恢复…（需要处理）"), #selector(showDataRecovery))
        menu.addItem(.separator())
        let version = NSMenuItem(title: L10n.tr("剪贴板 {0}", String(describing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.tr("开发版"))), action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        _ = item(L10n.tr("退出剪贴板"), #selector(quit))
        return menu
    }

    private func makeLanguageMenu() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.tr("语言 / Language"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for language in AppLanguage.allCases {
            let choice = NSMenuItem(title: language.nativeName, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = language.rawValue
            choice.state = settings.language == language ? .on : .off
            choice.isEnabled = !relocatingStorage && !favorites.library.isMutating && !shortcutPreferences.isVisible
                && NSApp.modalWindow == nil && storagePreferences.window?.attachedSheet == nil
                && favorites.library.window?.attachedSheet == nil
            if !choice.isEnabled { choice.toolTip = L10n.tr("请先完成当前操作，再切换语言。") }
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw),
              language != settings.language, !relocatingStorage, !favorites.library.isMutating,
              !shortcutPreferences.isVisible, NSApp.modalWindow == nil,
              storagePreferences.window?.attachedSheet == nil, favorites.library.window?.attachedSheet == nil else { return }
        var next = settings
        next.language = language
        do { try saveSettings(next) }
        catch { panel.showMessage(L10n.tr("语言保存失败，原语言保持不变。请检查数据目录后重试。")); return }
        refreshLanguageInterface()
    }

    private func refreshLanguageInterface() {
        pasteService.cancel()
        panel.dismiss()
        panel.previews.closeAll()
        let storageVisible = storagePreferences.isVisible
        storagePreferences.close()
        shortcutPreferences.close()
        L10n.language = settings.language
        saveError = saveError.map { L10n.relocalizeAppText($0) }
        lastPasteProgress = L10n.tr("尚未使用历史记录")
        lastKeyboardRoute = L10n.tr("尚未接收回车")
        configureEditMenu()
        // Build labels after the language changes; repositories and user data stay intact.
        favorites.refreshLanguage()
        storagePreferences = StoragePreferencesController()
        shortcutPreferences = ShortcutPreferencesController()
        configureHistoryPanel()
        refreshShortcutLabels()
        if storageVisible { storagePreferences.present(directory: dataStore.directoryURL) }
        else if !favorites.library.isVisible { showPanel() }
    }

    @objc private func clearHistory() {
        pasteService.cancel()
        if !storageReady { clearedWhileUnavailable = true }
        history.clear()
        historyChanged()
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        panel.update(entries: history.entries, paused: monitor.isPaused)
    }

    @objc private func openPermissions() {
        panel.dismiss()
        pasteService.openPermissionSettings()
    }

    @objc private func showPasteDiagnostics() {
        panel.dismiss()
        let alert = NSAlert()
        alert.messageText = L10n.tr("粘贴诊断")
        alert.informativeText = L10n.tr("版本：{0} · {1}\n辅助功能：{2}\n模拟按键：{3}\n目标程序：{4}\n回车路径：{5}\n最近状态：{6}", String(describing: RuntimeIdentity.version), String(describing: RuntimeIdentity.buildID), String(describing: AXIsProcessTrusted() ? L10n.tr("已允许") : L10n.tr("未允许")), String(describing: CGPreflightPostEventAccess() ? L10n.tr("已允许") : L10n.tr("未允许")), String(describing: targetApplication?.localizedName ?? L10n.tr("无")), String(describing: lastKeyboardRoute), String(describing: lastPasteProgress))
        alert.addButton(withTitle: L10n.tr("关闭"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openFavorites() {
        panel.dismiss()
        favorites.present()
    }

    @objc private func openStoragePreferences() {
        panel.dismiss()
        storagePreferences.present(directory:dataStore.directoryURL)
    }

    private func relocateStorage(to destination: URL, completion: @escaping (Result<URL,Error>) -> Void) {
        guard !favorites.library.isMutating else { completion(.failure(LocalStorageError(L10n.tr("收藏正在保存，请完成后再迁移。"))));return }
        guard storageReady, !storageBusy, let repository = favorites.repository else {
            completion(.failure(LocalStorageError(L10n.tr("当前数据尚未正常保存，请先通过“数据与恢复”恢复原位置。"))));return
        }
        storageBusy = true;relocatingStorage = true
        favorites.suspend()
        let source = dataStore, location = storageLocation
        storageQueue.async { [weak self] in
            repository.close()
            let result = Result { try StorageRelocator.migrate(source:source,to:destination,location:location) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.storageBusy = false;self.relocatingStorage = false
                switch result {
                case .success(let store): self.dataStore = store
                case .failure: self.dataStore = source
                }
                self.favorites.open(store:self.dataStore,available:true)
                self.historyChanged() // Persist copies collected while migration was in flight.
                completion(result.map { $0.directoryURL })
            }
        }
    }

    @objc private func openDataDirectory() {
        panel.dismiss()
        NSWorkspace.shared.open(dataStore.directoryURL)
    }

    @objc private func showDataRecovery() {
        panel.dismiss()
        let alert = NSAlert()
        alert.messageText = saveError == nil ? L10n.tr("数据已保存在本机") : L10n.tr("让记录恢复正常保存")
        alert.informativeText = (saveError ?? L10n.tr("当前没有需要处理的问题。"))
            + L10n.tr("\n\n先尝试“重试”。若文件损坏，可保留原文件后重建；可读记录和本次复制会保留。恢复副本只供手动取回，不会自动导回已删除内容。")
        alert.addButton(withTitle: saveError == nil ? L10n.tr("完成") : L10n.tr("重试"))
        alert.addButton(withTitle: L10n.tr("打开数据目录"))
        if !storageReady { alert.addButton(withTitle: L10n.tr("保留损坏文件并重建…")) }
        alert.addButton(withTitle: L10n.tr("取消"))
        NSApp.activate(ignoringOtherApps: true)
        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn, saveError != nil {
            retryStorage()
            showPanel()
            if saveError == nil { panel.showMessage(L10n.tr("已保存，可以继续使用。")) }
        } else if choice == .alertSecondButtonReturn {
            NSWorkspace.shared.open(dataStore.directoryURL)
        } else if choice == .alertThirdButtonReturn, !storageReady {
            let confirm = NSAlert()
            confirm.messageText = L10n.tr("保留原文件，再恢复记录功能？")
            confirm.informativeText = L10n.tr("只重建无法解析的文件。原文件会保存在数据目录的 Recovery 文件夹，可读历史和本次复制会保留。更新版本的数据不会被重建。")
            confirm.addButton(withTitle: L10n.tr("保留并恢复"))
            confirm.addButton(withTitle: L10n.tr("取消"))
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            storageQueue.sync {}
            do {
                _ = try dataStore.repairCorruptFiles(legacyHistoryURL: legacyHistoryURL, fallbackSettings: settings)
                retryStorage()
            } catch {
                saveError = error is DataFormatError
                    ? L10n.tr("数据由更新版本创建，请更新应用。原文件没有被修改。")
                    : L10n.tr("恢复未完成，原文件仍保留。请检查磁盘空间和目录写入权限。")
            }
            showPanel()
            if saveError == nil { panel.showMessage(L10n.tr("记录功能已恢复，原文件已保留在 Recovery 中。")) }
        }
    }

    @objc private func openLoginSettings() {
        panel.dismiss()
        launchAtLogin.openSettings()
    }

    private func registerConfiguredShortcut() {
        do { try hotKey.set(settings.shortcut); shortcutError = nil }
        catch { shortcutError = error.localizedDescription }
        hotKeyRegistered = hotKey.activeShortcut == settings.shortcut
        refreshShortcutLabels()
    }

    private func refreshShortcutLabels() {
        statusItem?.button?.toolTip = L10n.tr("剪贴板 · {0}", String(describing: shortcutName))
        statusItem?.button?.setAccessibilityLabel(L10n.tr("剪贴板"))
        panel.shortcutName = hotKey.activeShortcut?.displayName ?? shortcutName
    }

    @objc private func configureShortcut() {
        panel.dismiss()
        shortcutPreferences.present(current: settings.shortcut, isRegistered: hotKeyRegistered) { [weak self] shortcut in
            guard let self else { return }
            var next = self.settings
            next.shortcut = shortcut
            try self.hotKey.set(shortcut) { try self.saveSettings(next) }
            self.hotKeyRegistered = true
            self.shortcutError = nil
            self.refreshShortcutLabels()
        }
    }

    @objc private func configureLimit() {
        panel.dismiss()
        let alert = NSAlert()
        alert.messageText = L10n.tr("保留多少条历史？")
        alert.informativeText = L10n.tr("默认 10 条，可设置 1–50 条。超出上限时自动移除最早记录；调小后立即生效。")
        alert.addButton(withTitle: L10n.tr("保存"))
        alert.addButton(withTitle: L10n.tr("取消"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        field.stringValue = String(maxCount)
        field.placeholderString = "10"
        field.setAccessibilityLabel(L10n.tr("历史记录数量上限，1 到 50"))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let limit = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...History.maximumCount).contains(limit) else {
                alert.informativeText = L10n.tr("请输入 1 到 50 之间的整数。")
                continue
            }
            var next = settings
            next.maxHistoryCount = limit
            do { try saveSettings(next) }
            catch {
                alert.informativeText = L10n.tr("设置保存失败，请检查安装目录是否可写。")
                continue
            }
            history = History(entries: history.entries, maxCount: limit)
            historyChanged()
            break
        }
    }

    @objc private func configurePreview() {
        panel.dismiss()
        previewPreferences.edit(current: settings.preview) { [self] preview in
            var next = settings
            next.preview = preview
            try saveSettings(next)
            panel.previewSettings = preview
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
