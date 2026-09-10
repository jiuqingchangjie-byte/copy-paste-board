import Foundation
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Uses the system's login item state; a preference alone cannot enable login launches.
final class LaunchAtLoginService {
    enum Status: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case notFound
        case unknown
    }

    enum ConfigurationError: LocalizedError {
        case applicationBundleRequired
        case serviceUnavailable
        case operationFailed(enabling: Bool, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .applicationBundleRequired:
                return "请打开打包后的 ClipboardBoard.app，再设置登录自启。"
            case .serviceUnavailable:
                return "macOS 无法找到此应用的登录项。请将 ClipboardBoard.app 放在固定位置（建议“应用程序”），重新打开后再试。"
            case .operationFailed(let enabling, let error):
                return "无法\(enabling ? "开启" : "关闭")登录自启：\(error.localizedDescription)"
            }
        }
    }

    private let service: any LoginItemService
    private let isApplicationBundle: Bool

    init(service: any LoginItemService = SMAppService.mainApp,
         isApplicationBundle: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.service = service
        self.isApplicationBundle = isApplicationBundle
    }

    /// Read this when presenting settings, since users can change it in System Settings.
    var status: Status {
        switch service.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    var isEnabled: Bool { status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        let current = status
        if enabled && (current == .enabled || current == .requiresApproval) { return }
        if !enabled && current == .disabled { return }
        guard isApplicationBundle else { throw ConfigurationError.applicationBundleRequired }
        guard current != .notFound, current != .unknown else {
            throw ConfigurationError.serviceUnavailable
        }

        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            // Registration can succeed but still require user consent. Never report that as enabled.
            if enabled && status == .requiresApproval { return }
            throw ConfigurationError.operationFailed(enabling: enabled, underlying: error)
        }
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
