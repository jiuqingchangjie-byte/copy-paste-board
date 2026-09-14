import AppKit
import ClipboardCore
import Sparkle

// Sparkle owns update preferences and scheduling; do not duplicate these values
// in settings.json or reset them every time the app starts.
protocol SoftwareUpdateDriver: AnyObject {
    var canCheck: Bool { get }
    var automaticallyChecks: Bool { get set }
    var automaticallyDownloads: Bool { get set }
    var allowsAutomaticDownloads: Bool { get }
    func start() throws
    func check()
}

final class SoftwareUpdateService: NSObject {
    private let driver: SoftwareUpdateDriver
    private(set) var startupError: Error?
    private(set) var started = false
    var beforeCheck: (() -> Void)?

    init(driver: SoftwareUpdateDriver) { self.driver = driver }
    convenience init(canRestart: @escaping () -> Bool) {
        self.init(driver: SparkleUpdateDriver(canRestart: canRestart))
    }

    func start() {
        guard !started else { return }
        do { try driver.start(); started = true; startupError = nil }
        catch { startupError = error }
    }

    func appendMenuItems(to menu: NSMenu) {
        func item(_ title: String, _ action: Selector, enabled: Bool, checked: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            item.state = checked ? .on : .off
            menu.addItem(item)
        }
        item(L10n.tr("检查更新…"), #selector(checkForUpdates),
             enabled: startupError != nil || (started && driver.canCheck))
        item(L10n.tr("自动检查更新"), #selector(toggleAutomaticChecks),
             enabled: started, checked: driver.automaticallyChecks)
        item(L10n.tr("自动下载并安装更新"), #selector(toggleAutomaticDownloads),
             enabled: started && driver.allowsAutomaticDownloads, checked: driver.automaticallyDownloads)
    }

    @objc func checkForUpdates() {
        beforeCheck?()
        if let startupError {
            let alert = NSAlert()
            alert.messageText = L10n.tr("更新服务暂不可用")
            alert.informativeText = startupError.localizedDescription
            alert.addButton(withTitle: L10n.tr("关闭"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        } else if started, driver.canCheck { driver.check() }
    }

    @objc func toggleAutomaticChecks() {
        guard started else { return }
        driver.automaticallyChecks.toggle()
    }
    @objc func toggleAutomaticDownloads() {
        guard started, driver.allowsAutomaticDownloads else { return }
        driver.automaticallyDownloads.toggle()
    }
}

final class SparkleUpdateDriver: NSObject, SoftwareUpdateDriver, SPUUpdaterDelegate {
    private let canRestart: () -> Bool
    private var pendingRelaunch: Timer?
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    init(canRestart: @escaping () -> Bool) { self.canRestart = canRestart }
    var canCheck: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloads: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    var allowsAutomaticDownloads: Bool { controller.updater.allowsAutomaticUpdates }
    func start() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw NSError(domain: "ClipboardBoard.Update", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.tr("请从已安装的应用中检查更新。")])
        }
        try controller.updater.start()
    }
    func check() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeRelaunch(untilInvoking: installHandler)
    }

    func postponeRelaunch(untilInvoking installHandler: @escaping () -> Void) -> Bool {
        guard !canRestart() else { return false }
        // A storage move commits its pointer back on the main thread. Do not
        // block that thread or terminate halfway through the transaction.
        pendingRelaunch?.invalidate()
        pendingRelaunch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.canRestart() else { return }
            timer.invalidate()
            self.pendingRelaunch = nil
            installHandler()
        }
        return true
    }
}
