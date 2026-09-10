import AppKit
import Testing
@testable import ClipboardBoard

struct NativePasteCommandTests {
    private final class Backend: PasteCommandBackend {
        var capabilities = PasteCapabilities(accessibility: false, eventPosting: false)
        var menuResult: MenuPasteResult = .notAvailable
        var eventResult = true
        var menuCalls: [pid_t] = []
        var eventCalls = 0
        func pressPasteMenu(in pid: pid_t) -> MenuPasteResult { menuCalls.append(pid); return menuResult }
        func postPasteShortcut() -> Bool { eventCalls += 1; return eventResult }
    }

    @Test func accessibilityGrantCanPasteEvenWhenEventPreflightIsFalse() {
        let backend = Backend()
        backend.capabilities = PasteCapabilities(accessibility: true, eventPosting: false)
        backend.menuResult = .performed
        #expect(backend.capabilities.canPaste)
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .submitted)
        #expect(backend.menuCalls == [123])
        #expect(backend.eventCalls == 0)
    }

    @Test func eventGrantDoesNotRequireAnAccessibilityGrant() {
        let backend = Backend()
        backend.capabilities = PasteCapabilities(accessibility: false, eventPosting: true)
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .submitted)
        #expect(backend.menuCalls.isEmpty)
        #expect(backend.eventCalls == 1)
    }

    @Test func successfulNativePasteIsNeverFollowedByASecondKeyboardPaste() {
        let backend = Backend()
        backend.capabilities = PasteCapabilities(accessibility: true, eventPosting: true)
        backend.menuResult = .performed
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .submitted)
        #expect(backend.eventCalls == 0)
    }

    @Test func nativeTimeoutDoesNotCauseADuplicatePaste() {
        let backend = Backend()
        backend.capabilities = PasteCapabilities(accessibility: true, eventPosting: true)
        backend.menuResult = .uncertain
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .uncertain)
        #expect(backend.eventCalls == 0)
    }

    @Test func missingMenuFallsBackOnlyWhenKeyboardPostingIsAllowed() {
        let backend = Backend()
        backend.capabilities = PasteCapabilities(accessibility: true, eventPosting: false)
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .unavailable)
        #expect(backend.eventCalls == 0)
        backend.capabilities = PasteCapabilities(accessibility: true, eventPosting: true)
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .submitted)
        #expect(backend.eventCalls == 1)
    }

    @Test func absentPermissionsNeverInvokeEitherAction() {
        let backend = Backend()
        #expect(!backend.capabilities.canPaste)
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .unavailable)
        #expect(backend.menuCalls.isEmpty)
        #expect(backend.eventCalls == 0)
    }

    @Test func disabledPasteCommandDoesNotPretendAKeyboardFallbackSucceeded() {
        let backend = Backend()
        backend.capabilities = PasteCapabilities(accessibility: true, eventPosting: true)
        backend.menuResult = .disabled
        #expect(NativePasteCommand.deliver(to: 123, using: backend) == .unavailable)
        #expect(backend.eventCalls == 0)
    }
}
