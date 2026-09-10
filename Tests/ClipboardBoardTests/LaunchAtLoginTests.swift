import Foundation
import AppKit
import ServiceManagement
import Testing
@testable import ClipboardBoard

struct LaunchAtLoginTests {
    private final class FakeLoginItem: LoginItemService {
        var status: SMAppService.Status = .notRegistered
        var registrationCount = 0
        var unregistrationCount = 0
        var registrationStatus: SMAppService.Status = .enabled
        var registrationError: Error?
        var unregistrationError: Error?

        func register() throws {
            registrationCount += 1
            if let registrationError {
                if registrationStatus == .requiresApproval { status = registrationStatus }
                throw registrationError
            }
            status = registrationStatus
        }

        func unregister() throws {
            unregistrationCount += 1
            if let unregistrationError { throw unregistrationError }
            status = .notRegistered
        }
    }

    @Test func missingRegistrationCanBeRetriedWithoutPretendingItIsEnabled() throws {
        let system = FakeLoginItem()
        system.status = .notFound
        let service = LaunchAtLoginService(service: system, isApplicationBundle: true)
        #expect(!service.isEnabled)
        try service.setEnabled(true)
        #expect(system.registrationCount == 1)
        #expect(service.isEnabled)
        system.status = .notFound
        system.registrationError = NSError(domain: "test", code: 7)
        #expect(throws: (any Error).self) { try service.setEnabled(true) }
        #expect(!service.isEnabled)
    }

    @Test func reflectsChangesMadeOutsideTheApp() {
        let system = FakeLoginItem()
        let service = LaunchAtLoginService(service: system, isApplicationBundle: true)
        #expect(service.status == .disabled)
        system.status = .enabled
        #expect(service.isEnabled)
        system.status = .requiresApproval
        #expect(service.status == .requiresApproval)
        #expect(!service.isEnabled)
        system.status = .notFound
        #expect(service.status == .notFound)
        #expect(!service.isEnabled)
    }

    @Test func repeatedEnablingAndDisablingAreIdempotent() throws {
        let system = FakeLoginItem()
        let service = LaunchAtLoginService(service: system, isApplicationBundle: true)
        try service.setEnabled(false)
        #expect(system.unregistrationCount == 0)
        try service.setEnabled(true)
        try service.setEnabled(true)
        #expect(service.isEnabled)
        #expect(system.registrationCount == 1)
        try service.setEnabled(false)
        try service.setEnabled(false)
        #expect(service.status == .disabled)
        #expect(system.unregistrationCount == 1)
    }

    @Test func pendingApprovalDoesNotReregisterAndCanBeCancelled() throws {
        let system = FakeLoginItem()
        system.status = .requiresApproval
        let service = LaunchAtLoginService(service: system, isApplicationBundle: true)
        try service.setEnabled(true)
        #expect(system.registrationCount == 0)
        #expect(!service.isEnabled)
        try service.setEnabled(false)
        #expect(system.unregistrationCount == 1)
        #expect(service.status == .disabled)
    }

    @Test func deniedApprovalIsReportedAsPendingInsteadOfEnabled() throws {
        let system = FakeLoginItem()
        system.registrationStatus = .requiresApproval
        system.registrationError = NSError(domain: "TestServiceManagement", code: 1)
        let service = LaunchAtLoginService(service: system, isApplicationBundle: true)
        try service.setEnabled(true)
        #expect(service.status == .requiresApproval)
        #expect(!service.isEnabled)
    }

    @Test func failedOperationsPreserveRealStateAndExposeErrors() {
        let system = FakeLoginItem()
        let error = NSError(domain: "TestServiceManagement", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "test registration failure"])
        system.registrationError = error
        let service = LaunchAtLoginService(service: system, isApplicationBundle: true)
        do {
            try service.setEnabled(true)
            Issue.record("Registration failure must be reported")
        } catch {
            #expect(error.localizedDescription.contains("test registration failure"))
        }
        #expect(service.status == .disabled)
        system.status = .enabled
        system.unregistrationError = error
        #expect(throws: LaunchAtLoginService.ConfigurationError.self) {
            try service.setEnabled(false)
        }
        #expect(service.isEnabled)
    }

    @Test func commandLineExecutableCannotRegisterALoginItem() {
        let system = FakeLoginItem()
        let service = LaunchAtLoginService(service: system, isApplicationBundle: false)
        #expect(throws: LaunchAtLoginService.ConfigurationError.self) {
            try service.setEnabled(true)
        }
        #expect(system.registrationCount == 0)
    }

    @Test @MainActor func switchShowsRealStateAndRefreshesExternalChanges() {
        _ = NSApplication.shared
        let system = FakeLoginItem()
        let view = LaunchAtLoginMenuView(service: LaunchAtLoginService(service: system, isApplicationBundle: true), onOpenSettings: {})
        #expect(view.toggle.state == .off)
        #expect(view.statusLabel.stringValue == "已关闭")
        system.status = .enabled
        view.refresh()
        #expect(view.toggle.state == .on)
        #expect(view.statusLabel.stringValue == "已开启")
        system.status = .requiresApproval
        view.refresh()
        #expect(view.toggle.state == .on)
        #expect(view.statusLabel.stringValue == "等待系统批准 · 尚未生效")
        system.status = .notFound
        view.refresh()
        #expect(view.toggle.isEnabled)
        #expect(view.statusLabel.stringValue == "尚未找到登录项 · 可尝试开启")
    }

    @Test @MainActor func clickingTheSwitchChangesTheServiceAndShowsTheResult() {
        _ = NSApplication.shared
        let system = FakeLoginItem()
        let view = LaunchAtLoginMenuView(service: LaunchAtLoginService(service: system, isApplicationBundle: true), onOpenSettings: {})
        view.toggle.performClick(nil)
        #expect(system.registrationCount == 1)
        #expect(view.toggle.state == .on)
        #expect(view.statusLabel.stringValue == "已开启")
        view.toggle.performClick(nil)
        #expect(system.unregistrationCount == 1)
        #expect(view.toggle.state == .off)
        #expect(view.statusLabel.stringValue == "已关闭")
        system.status = .requiresApproval
        view.refresh()
        view.toggle.performClick(nil)
        #expect(system.unregistrationCount == 2)
        #expect(view.statusLabel.stringValue == "已关闭")
    }

    @Test @MainActor func failedChangeRestoresTheSwitchAndExplainsTheCurrentState() {
        _ = NSApplication.shared
        let system = FakeLoginItem()
        let error = NSError(domain: "TestServiceManagement", code: 1)
        system.registrationError = error
        let view = LaunchAtLoginMenuView(service: LaunchAtLoginService(service: system, isApplicationBundle: true), onOpenSettings: {})
        view.toggle.performClick(nil)
        #expect(view.toggle.state == .off)
        #expect(view.statusLabel.stringValue == "更改失败 · 已关闭")
        system.status = .enabled
        system.unregistrationError = error
        view.refresh()
        view.toggle.performClick(nil)
        #expect(view.toggle.state == .on)
        #expect(view.statusLabel.stringValue == "更改失败 · 已开启")
    }

    @Test @MainActor func renderSwitchStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["CLIPBOARD_PREVIEW_DIR"] else { return }
        _ = NSApplication.shared
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 198))
            root.material = .menu
            root.state = .active
            root.appearance = NSAppearance(named: appearance)
            let statuses: [SMAppService.Status] = [.notRegistered, .enabled, .requiresApproval]
            for (index, status) in statuses.enumerated() {
                let system = FakeLoginItem()
                system.status = status
                let view = LaunchAtLoginMenuView(service: LaunchAtLoginService(service: system, isApplicationBundle: true), onOpenSettings: {})
                view.setFrameOrigin(NSPoint(x: 0, y: 132 - index * 66))
                root.addSubview(view)
            }
            root.layoutSubtreeIfNeeded()
            let representation = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: representation)
            let data = try #require(representation.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(appearance == .aqua ? "login-switch-light.png" : "login-switch-dark.png"))
        }
    }
}
