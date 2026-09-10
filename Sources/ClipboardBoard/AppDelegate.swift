import AppKit
import ApplicationServices
import ClipboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PasteboardMonitor()
    private let hotKey = GlobalHotKey()
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
    private let dataStore = AppDataStore(applicationURL: Bundle.main.bundleURL)
    private var storage: HistoryStorage { dataStore.history }
    private var storageReady = false
    private let storageQueue = DispatchQueue(label: "ClipboardBoard.storage", qos: .utility)
    private var saveError: String?
    private var permissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var hotKeyRegistered = false
    private var lastPasteProgress = "尚未使用历史记录"

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
        configureEditMenu()
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApplication = front }
        loadStoredData()
        let origin = settings.panelOrigin.map { NSPoint(x: $0[0], y: $0[1]) }
        panel = HistoryPanelController(origin: origin)
        pasteService.onProgress = { [weak self] in self?.lastPasteProgress = $0 }
        panel.onOriginChanged = { [weak self] origin in
            guard let self else { return }
            var next = self.settings
            next.panelOrigin = [Double(origin.x), Double(origin.y)]
            do { try self.saveSettings(next) }
            catch { self.panel.showMessage("位置保存失败，请检查安装目录的写入权限。") }
        }
        panel.onPaste = { [weak self] in self?.use($0) }
        panel.onDismiss = { [weak self] in
            guard let self, !self.dismissingForPaste else { return }
            self.pasteService.cancel()
        }
        panel.onDeleteEntry = { [weak self] id in
            guard let self else { return }
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "剪贴板")
            button.image?.isTemplate = true
            button.toolTip = "剪贴板 · ⌥V"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        hotKey.onPress = { [weak self] in self?.togglePanel() }
        hotKeyRegistered = hotKey.register() == noErr
        monitor.onCapture = { [weak self] payload, source in
            guard let self else { return }
            if self.history.insert(HistoryEntry(payload: payload, sourceName: source)) { self.historyChanged() }
        }
        monitor.start()
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
            catch { saveError = "数据保存失败，请将应用放在可写目录后重启。" }
            showPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        // Finish pending atomic saves before quitting, including a pending clear.
        storageQueue.sync {}
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private func historyChanged() {
        panel.update(entries: history.entries, paused: monitor.isPaused)
        guard storageReady else {
            panel.showMessage("数据目录尚不可用，本次记录仅在内存中。请检查安装目录。")
            return
        }
        let entries = history.entries
        let storage = storage
        storageQueue.async { [weak self] in
            do {
                try storage.save(entries)
                DispatchQueue.main.async { self?.saveError = nil }
            } catch {
                DispatchQueue.main.async {
                    self?.saveError = "历史记录保存失败，当前记录仅在本次运行有效。"
                    self?.panel.showMessage(self?.saveError ?? "")
                }
            }
        }
    }

    private func loadStoredData() {
        let legacyLimit = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        let legacySettings = AppSettings(
            maxHistoryCount: legacyLimit > 0 ? legacyLimit : 10,
            panelOrigin: UserDefaults.standard.array(forKey: "historyPanelOrigin") as? [Double],
            hasLaunched: UserDefaults.standard.bool(forKey: "hasLaunched"))
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = support.appendingPathComponent("ClipboardBoard/history.json")
        do {
            try dataStore.migrateLegacyIfNeeded(historyURL: legacyURL, settings: legacySettings)
            settings = try dataStore.loadSettings()
            let storedEntries = try storage.load()
            history = History(entries: storedEntries, maxCount: maxCount)
            if history.entries != storedEntries { try storage.save(history.entries) }
            storageReady = true
            for key in ["maxHistoryCount", "historyPanelOrigin", "hasLaunched"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        } catch {
            // Reading the old file is safe; never overwrite it after a failed migration.
            settings = (try? dataStore.loadSettings()) ?? legacySettings
            let source = FileManager.default.fileExists(atPath: storage.fileURL.path)
                ? storage : HistoryStorage(fileURL: legacyURL)
            history = History(entries: (try? source.load()) ?? [], maxCount: maxCount)
            saveError = "数据迁移或读取失败，原文件已保留；请检查安装目录。"
        }
    }

    private func saveSettings(_ next: AppSettings) throws {
        guard storageReady else {
            throw NSError(domain: "ClipboardBoard.Storage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "数据目录不可用，请将应用放在可写目录后重启。"])
        }
        try dataStore.saveSettings(next)
        settings = next
    }

    private func configureEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = appMenu.addItem(withTitle: "退出剪贴板", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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
        if !hotKeyRegistered { panel.showMessage("⌥V 注册失败，可能已被其他应用占用。可点击菜单栏图标打开。") }
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
            self.lastPasteProgress = String(describing: outcome)
            switch outcome {
            case .eventPosted: break
            case .permissionRequired:
                if !self.panel.isVisible { self.showPanel() }
                self.panel.showMessage("未粘贴：请点击“去授权”，允许辅助功能后再使用。")
            case .targetUnavailable:
                self.showPanel()
                self.panel.showMessage("未粘贴：请先点击目标输入框，再按 ⌥V 选择记录。")
            case .focusChanged:
                break // Respect a deliberate switch to another application.
            case .keysStillPressed:
                if !self.panel.isVisible { self.showPanel() }
                self.panel.showMessage("请松开 ⌥、⌘ 和回车键，再按一次回车粘贴。")
            case .clipboardChanged:
                self.showPanel()
                self.panel.showMessage("等待粘贴时发生了新的复制，请重新选择历史记录。")
            case .clipboardWriteFailed:
                self.panel.showMessage("无法使用这条记录：文件可能已移动，或内容已损坏。")
            case .deliveryUncertain:
                self.showPanel()
                self.panel.showMessage("目标应用未及时确认，请先检查输入框，避免重复粘贴。")
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
        _ = item("打开历史记录    ⌥V", #selector(togglePanel))
        _ = item("历史记录上限：\(maxCount) 条…", #selector(configureLimit))
        let login = NSMenuItem(title: "登录时自动启动", action: nil, keyEquivalent: "")
        login.view = LaunchAtLoginMenuView(service: launchAtLogin) { [weak self, weak menu] in
            menu?.cancelTracking()
            self?.openLoginSettings()
        }
        menu.addItem(login)
        _ = item(monitor.isPaused ? "继续记录" : "暂停记录", #selector(togglePause))
        menu.addItem(.separator())
        let clear = item("清空全部历史", #selector(clearHistory))
        clear.isEnabled = !history.entries.isEmpty
        _ = item("辅助功能权限…", #selector(openPermissions))
        _ = item("粘贴诊断…", #selector(showPasteDiagnostics))
        _ = item("打开数据目录", #selector(openDataDirectory))
        menu.addItem(.separator())
        let version = NSMenuItem(title: "剪贴板 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        _ = item("退出剪贴板", #selector(quit))
        return menu
    }

    @objc private func clearHistory() {
        pasteService.cancel()
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
        alert.messageText = "粘贴诊断"
        alert.informativeText = "辅助功能：\(AXIsProcessTrusted() ? "已允许" : "未允许")\n模拟按键：\(CGPreflightPostEventAccess() ? "已允许" : "未允许")\n目标程序：\(targetApplication?.localizedName ?? "无")\n最近状态：\(lastPasteProgress)"
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openDataDirectory() {
        panel.dismiss()
        NSWorkspace.shared.open(dataStore.directoryURL)
    }

    @objc private func openLoginSettings() {
        panel.dismiss()
        launchAtLogin.openSettings()
    }

    @objc private func configureLimit() {
        panel.dismiss()
        let alert = NSAlert()
        alert.messageText = "保留多少条历史？"
        alert.informativeText = "默认 10 条，可设置 1–1000 条。超出上限时自动移除最早记录；调小后立即生效。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        field.stringValue = String(maxCount)
        field.placeholderString = "10"
        field.setAccessibilityLabel("历史记录数量上限，1 到 1000")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let limit = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...1000).contains(limit) else {
                alert.informativeText = "请输入 1 到 1000 之间的整数。"
                continue
            }
            var next = settings
            next.maxHistoryCount = limit
            do { try saveSettings(next) }
            catch {
                alert.informativeText = "设置保存失败，请检查安装目录是否可写。"
                continue
            }
            history = History(entries: history.entries, maxCount: limit)
            historyChanged()
            break
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
