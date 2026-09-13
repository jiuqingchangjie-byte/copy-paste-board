import ClipboardCore
import AppKit
import ApplicationServices
import Carbon

// Injected in tests: no keystrokes are sent to the user's apps.
protocol PasteEnvironment: AnyObject {
    var hasPermission: Bool { get }
    var ownPID: pid_t { get }
    var frontmostPID: pid_t? { get }
    var clipboardChangeCount: Int { get }
    var keysAreReleased: Bool { get }
    func isRunning(_ pid: pid_t) -> Bool
    func activate(_ pid: pid_t) -> Bool
    func postPasteShortcut() -> Bool
    func captureTarget(_ pid: pid_t?)
    func restoreTargetFocus(_ pid: pid_t) -> Bool
    func deliverPaste(into pid: pid_t) -> PasteDelivery
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void)
}

extension PasteEnvironment {
    func captureTarget(_ pid: pid_t?) {}
    func restoreTargetFocus(_ pid: pid_t) -> Bool { true }
    func deliverPaste(into pid: pid_t) -> PasteDelivery { postPasteShortcut() ? .submitted : .unavailable }
}

final class PasteService {
    enum Outcome: Equatable {
        case eventPosted, permissionRequired, targetUnavailable, focusChanged, keysStillPressed, clipboardChanged, clipboardWriteFailed, deliveryUncertain
        var localizedDescription: String {
            switch self {
            case .eventPosted: return L10n.tr("已提交粘贴")
            case .permissionRequired: return L10n.tr("需要辅助功能权限")
            case .targetUnavailable: return L10n.tr("目标程序不可用")
            case .focusChanged: return L10n.tr("输入焦点已改变")
            case .keysStillPressed: return L10n.tr("按键尚未松开")
            case .clipboardChanged: return L10n.tr("剪贴板内容已改变")
            case .clipboardWriteFailed: return L10n.tr("剪贴板写入失败")
            case .deliveryUncertain: return L10n.tr("粘贴结果尚未确认")
            }
        }
    }
    private var operationID = UUID()
    private let environment: PasteEnvironment
    var onProgress: ((String) -> Void)?

    init(environment: PasteEnvironment = SystemPasteEnvironment()) { self.environment = environment }
    var hasPermission: Bool { environment.hasPermission }
    func captureTarget(_ target: NSRunningApplication?) { environment.captureTarget(target?.processIdentifier) }

    func openPermissionSettings() {
        if !hasPermission {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func cancel() { operationID = UUID() }

    func paste(into target: NSRunningApplication?, prepareClipboard: () -> Bool,
               beforeActivation: @escaping () -> Void,
               completion: @escaping (Outcome) -> Void) {
        paste(intoPID: target?.processIdentifier, prepareClipboard: prepareClipboard,
              beforeActivation: beforeActivation, completion: completion)
    }

    func paste(intoPID pid: pid_t?, prepareClipboard: () -> Bool = { true }, beforeActivation: @escaping () -> Void,
               completion: @escaping (Outcome) -> Void) {
        cancel()
        onProgress?(L10n.tr("已接收粘贴请求"))
        guard hasPermission else { completion(.permissionRequired); return }
        guard let pid, pid != environment.ownPID, environment.isRunning(pid) else {
            completion(.targetUnavailable)
            return
        }
        // Enter and double-click mean paste. Do not silently turn either action
        // into a clipboard-only copy when permission or the target is missing.
        guard prepareClipboard() else { completion(.clipboardWriteFailed); return }
        let operation = operationID
        let clipboardVersion = environment.clipboardChangeCount
        // Keep the panel open while Return is held so key repeats cannot enter the editor.
        waitForRelease(pid, operation: operation, clipboardVersion: clipboardVersion,
                       initialFront: environment.frontmostPID, attempt: 0,
                       beforeActivation: beforeActivation, completion: completion)
    }

    private func waitForRelease(_ pid: pid_t, operation: UUID, clipboardVersion: Int,
                                 initialFront: pid_t?, attempt: Int, beforeActivation: @escaping () -> Void,
                                 completion: @escaping (Outcome) -> Void) {
        guard operationID == operation else { return }
        guard validate(pid, clipboardVersion: clipboardVersion, completion: completion) else { return }
        guard environment.frontmostPID == initialFront else { completion(.focusChanged); return }
        guard environment.keysAreReleased else {
            guard attempt < 60 else { completion(.keysStillPressed); return }
            environment.schedule(after: 0.05) { [weak self] in
                self?.waitForRelease(pid, operation: operation, clipboardVersion: clipboardVersion,
                                     initialFront: initialFront, attempt: attempt + 1,
                                     beforeActivation: beforeActivation, completion: completion)
            }
            return
        }
        beforeActivation()
        onProgress?(L10n.tr("正在恢复目标程序"))
        guard operationID == operation else { return }
        // A nonactivating panel can own key focus while frontmostApplication is
        // still the old app. Activate the target even when its PID already matches.
        guard environment.activate(pid) else { completion(.targetUnavailable); return }
        environment.schedule(after: 0.15) { [weak self] in
            self?.waitForTarget(pid, operation: operation, clipboardVersion: clipboardVersion,
                                attempt: 0, completion: completion)
        }
    }

    private func waitForTarget(_ pid: pid_t, operation: UUID, clipboardVersion: Int,
                               attempt: Int, completion: @escaping (Outcome) -> Void) {
        guard operationID == operation else { return }
        guard validate(pid, clipboardVersion: clipboardVersion, completion: completion) else { return }
        let focused = environment.frontmostPID == pid
        if !focused, environment.frontmostPID != environment.ownPID && environment.frontmostPID != nil {
            completion(.focusChanged)
            return
        }
        guard focused, environment.keysAreReleased else {
            guard attempt < 20 else {
                completion(focused ? .keysStillPressed : .targetUnavailable)
                return
            }
            environment.schedule(after: 0.05) { [weak self] in
                self?.waitForTarget(pid, operation: operation, clipboardVersion: clipboardVersion,
                                    attempt: attempt + 1, completion: completion)
            }
            return
        }
        guard environment.restoreTargetFocus(pid) else { completion(.targetUnavailable); return }
        guard environment.frontmostPID == pid else { completion(.focusChanged); return }
        onProgress?(L10n.tr("已恢复原输入框，正在提交粘贴"))
        switch environment.deliverPaste(into: pid) {
        case .submitted: completion(.eventPosted)
        case .unavailable: completion(.targetUnavailable)
        case .uncertain: completion(.deliveryUncertain)
        }
    }

    private func validate(_ pid: pid_t, clipboardVersion: Int, completion: (Outcome) -> Void) -> Bool {
        guard environment.hasPermission else { completion(.permissionRequired); return false }
        guard environment.isRunning(pid) else { completion(.targetUnavailable); return false }
        guard environment.clipboardChangeCount == clipboardVersion else { completion(.clipboardChanged); return false }
        return true
    }
}

final class SystemPasteEnvironment: PasteEnvironment, PasteCommandBackend {
    private let inputFocus = OriginalInputFocus()
    var capabilities: PasteCapabilities {
        PasteCapabilities(accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess())
    }
    var hasPermission: Bool { capabilities.canPaste }
    func captureTarget(_ pid: pid_t?) { inputFocus.capture(in: pid) }
    func restoreTargetFocus(_ pid: pid_t) -> Bool { inputFocus.restore(in: pid) }
    func pressPasteMenu(in pid: pid_t) -> MenuPasteResult { AccessibilityPasteMenu.perform(in: pid) }
    func deliverPaste(into pid: pid_t) -> PasteDelivery { NativePasteCommand.deliver(to: pid, using: self) }
    var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }
    var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var clipboardChangeCount: Int { NSPasteboard.general.changeCount }
    var keysAreReleased: Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
        return flags.isEmpty
            && !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Return))
            && !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_KeypadEnter))
    }

    func isRunning(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
    }

    func activate(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    func postPasteShortcut() -> Bool {
        guard CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .privateState) else { return false }
        // Normal system keyboard routing, including explicit modifier transitions.
        let strokes: [(CGKeyCode, Bool, CGEventFlags)] = [
            (CGKeyCode(kVK_Command), true, .maskCommand),
            (CGKeyCode(kVK_ANSI_V), true, .maskCommand),
            (CGKeyCode(kVK_ANSI_V), false, .maskCommand),
            (CGKeyCode(kVK_Command), false, [])
        ]
        let events = strokes.compactMap { key, down, flags -> CGEvent? in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return nil }
            event.flags = flags
            return event
        }
        guard events.count == strokes.count else { return false }
        // Never cancel midway through the group: always release V and Command.
        for event in events { event.post(tap: .cghidEventTap) }
        return true
    }

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}
