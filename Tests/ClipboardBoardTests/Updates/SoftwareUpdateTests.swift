import AppKit
import Testing
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct SoftwareUpdateTests {
    private final class Driver: SoftwareUpdateDriver {
        var canCheck = true
        var automaticallyChecks = false
        var automaticallyDownloads = true
        var allowsAutomaticDownloads: Bool { automaticallyChecks }
        var starts = 0
        var checks = 0
        var failure: Error?
        func start() throws { starts += 1; if let failure { throw failure } }
        func check() { checks += 1 }
    }

    @Test func startupPreservesExistingPreferencesAndStartsOnlyOnce() {
        let driver = Driver()
        let service = SoftwareUpdateService(driver: driver)
        service.start(); service.start()
        #expect(driver.starts == 1)
        #expect(!driver.automaticallyChecks && driver.automaticallyDownloads)
    }

    @Test func userChangesAreWrittenToTheUpdaterAndSurviveServiceRecreation() {
        let driver = Driver()
        let service = SoftwareUpdateService(driver: driver)
        service.start()
        service.toggleAutomaticChecks()
        service.toggleAutomaticDownloads()
        #expect(driver.automaticallyChecks && !driver.automaticallyDownloads)
        SoftwareUpdateService(driver: driver).start()
        #expect(driver.automaticallyChecks && !driver.automaticallyDownloads)
    }

    @Test func disablingChecksPreservesDownloadChoiceButDisablesItsControl() {
        _ = NSApplication.shared
        let driver = Driver()
        let service = SoftwareUpdateService(driver: driver)
        service.start()
        service.toggleAutomaticDownloads()
        #expect(driver.automaticallyDownloads)
        let menu = NSMenu(); menu.autoenablesItems = false
        service.appendMenuItems(to: menu)
        #expect(menu.items.count == 3)
        #expect(menu.items[0].isEnabled)
        #expect(menu.items[1].state == .off)
        #expect(!menu.items[2].isEnabled && menu.items[2].state == .on)
    }

    @Test func inProgressCheckCannotStartAnotherSession() {
        let driver = Driver()
        let service = SoftwareUpdateService(driver: driver)
        service.start()
        var dismissed = false
        service.beforeCheck = { dismissed = true }
        service.checkForUpdates()
        #expect(driver.checks == 1 && dismissed)
        driver.canCheck = false
        service.checkForUpdates()
        #expect(driver.checks == 1)
    }

    @Test func startupFailureDisablesSettingsAndCanBeRetried() {
        _ = NSApplication.shared
        let driver = Driver()
        driver.failure = NSError(domain: "test", code: 1)
        let service = SoftwareUpdateService(driver: driver)
        service.start()
        #expect(!service.started && service.startupError != nil)
        service.toggleAutomaticChecks()
        #expect(!driver.automaticallyChecks)
        let menu = NSMenu(); service.appendMenuItems(to: menu)
        #expect(menu.items[0].isEnabled) // exposes the startup error to the user
        #expect(!menu.items[1].isEnabled && !menu.items[2].isEnabled)
        driver.failure = nil
        service.start()
        #expect(service.started && service.startupError == nil)
    }

    @Test func updateRelaunchWaitsForStorageWithoutBlockingTheMainThread() async throws {
        var ready = false
        let driver = SparkleUpdateDriver(canRestart: { ready })
        var resumed = 0
        #expect(driver.postponeRelaunch { resumed += 1 })
        try await Task.sleep(for: .milliseconds(600))
        #expect(resumed == 0)
        ready = true
        try await Task.sleep(for: .milliseconds(600))
        #expect(resumed == 1)
        #expect(!driver.postponeRelaunch { resumed += 1 })
        #expect(resumed == 1) // Sparkle handles the immediate case itself.
    }
}
