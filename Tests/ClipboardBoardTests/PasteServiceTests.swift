import AppKit
import Testing
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct PasteServiceTests {
    enum WaitingPhase: CaseIterable, Sendable {
        case releasingKeys, restoringTarget
    }

    @Test func postsOnceAfterPanelDismissalAndTargetRestoration() {
        let environment = MockPasteEnvironment()
        environment.frontmostPID = environment.ownPID
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        var dismissals = 0

        service.paste(intoPID: environment.targetPID, prepareClipboard: {
            environment.trace.append("prepare")
            environment.clipboardChangeCount += 1
            return true
        }, beforeActivation: {
            environment.trace.append("dismiss")
            dismissals += 1
            #expect(environment.activatedPIDs.isEmpty)
        }) { outcomes.append($0) }

        #expect(dismissals == 1)
        #expect(environment.activatedPIDs == [environment.targetPID])
        #expect(environment.postAttempts == 0)
        #expect(outcomes.isEmpty)
        #expect(environment.scheduledDelays.first == 0.15)
        #expect(environment.trace == ["prepare", "dismiss", "activate"])

        environment.drain()

        #expect(environment.postAttempts == 1)
        #expect(outcomes == [.eventPosted])
        #expect(environment.pendingCount == 0)
        #expect(environment.elapsed >= 0.15)
        #expect(environment.trace == ["prepare", "dismiss", "activate", "post"])
        environment.drain()
        #expect(environment.postAttempts == 1)
    }

    @Test func activatesTargetEvenWhenItWasAlreadyFrontmost() {
        let environment = MockPasteEnvironment()
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []

        #expect(environment.frontmostPID == environment.targetPID)
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }
        environment.drain()

        #expect(environment.activatedPIDs == [environment.targetPID])
        #expect(environment.postAttempts == 1)
        #expect(outcomes == [.eventPosted])
    }

    @Test func keepsPanelOpenUntilPhysicalKeysAreReleased() {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = false
        let service = PasteService(environment: environment)
        var dismissals = 0
        var outcomes: [PasteService.Outcome] = []

        service.paste(intoPID: environment.targetPID, beforeActivation: { dismissals += 1 }) {
            outcomes.append($0)
        }
        #expect(environment.runNext())
        #expect(environment.runNext())
        #expect(dismissals == 0)
        #expect(environment.activatedPIDs.isEmpty)
        #expect(environment.postAttempts == 0)

        environment.keysAreReleased = true
        #expect(environment.runNext())
        #expect(dismissals == 1)
        #expect(environment.postAttempts == 0)
        #expect(outcomes.isEmpty)
        environment.drain()
        #expect(environment.postAttempts == 1)
        #expect(outcomes == [.eventPosted])
    }

    @Test(arguments: WaitingPhase.allCases)
    func cancellationStopsPendingWork(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        var dismissals = 0
        service.paste(intoPID: environment.targetPID, beforeActivation: { dismissals += 1 }) {
            outcomes.append($0)
        }

        service.cancel()
        environment.keysAreReleased = true
        environment.drain()

        #expect(environment.postAttempts == 0)
        #expect(outcomes.isEmpty)
        #expect(dismissals == (phase == .restoringTarget ? 1 : 0))
        #expect(environment.pendingCount == 0)
    }

    @Test(arguments: WaitingPhase.allCases)
    func deliberateFocusSwitchNeverPastesIntoAnotherApplication(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        var dismissals = 0
        service.paste(intoPID: environment.targetPID, beforeActivation: { dismissals += 1 }) {
            outcomes.append($0)
        }

        environment.frontmostPID = 999
        environment.keysAreReleased = true
        environment.drain()

        #expect(environment.postAttempts == 0)
        #expect(outcomes == [.focusChanged])
        #expect(dismissals == (phase == .restoringTarget ? 1 : 0))
    }

    @Test(arguments: WaitingPhase.allCases)
    func targetExitStopsPendingPaste(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }

        environment.runningPIDs.remove(environment.targetPID)
        environment.keysAreReleased = true
        environment.drain()

        #expect(environment.postAttempts == 0)
        #expect(outcomes == [.targetUnavailable])
        #expect(environment.pendingCount == 0)
    }

    @Test(arguments: WaitingPhase.allCases)
    func permissionRevocationStopsPendingPaste(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }

        environment.hasPermission = false
        environment.keysAreReleased = true
        environment.drain()

        #expect(!service.hasPermission)
        #expect(environment.postAttempts == 0)
        #expect(outcomes == [.permissionRequired])
        #expect(environment.pendingCount == 0)
    }

    @Test(arguments: WaitingPhase.allCases)
    func aNewCopyInvalidatesTheSelectedClipboardVersion(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }

        environment.clipboardChangeCount += 1
        environment.keysAreReleased = true
        environment.drain()

        #expect(environment.postAttempts == 0)
        #expect(outcomes == [.clipboardChanged])
        #expect(environment.pendingCount == 0)
    }

    @Test func invalidTargetsAreRejectedWithoutDismissingThePanel() {
        let environment = MockPasteEnvironment()
        let service = PasteService(environment: environment)
        let invalidTargets: [pid_t?] = [nil, environment.ownPID, 999]

        for target in invalidTargets {
            var outcomes: [PasteService.Outcome] = []
            var dismissals = 0
            var preparations = 0
            let originalClipboardVersion = environment.clipboardChangeCount
            service.paste(intoPID: target, prepareClipboard: {
                preparations += 1
                environment.clipboardChangeCount += 1
                return true
            }, beforeActivation: { dismissals += 1 }) { outcomes.append($0) }
            #expect(outcomes == [.targetUnavailable])
            #expect(dismissals == 0)
            #expect(preparations == 0)
            #expect(environment.clipboardChangeCount == originalClipboardVersion)
        }
        #expect(environment.activatedPIDs.isEmpty)
        #expect(environment.postAttempts == 0)
        #expect(environment.pendingCount == 0)
    }

    @Test func missingPermissionDoesNotActivateOrSendEvents() {
        let environment = MockPasteEnvironment()
        environment.hasPermission = false
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        var dismissals = 0
        var preparations = 0
        let originalClipboardVersion = environment.clipboardChangeCount

        service.paste(intoPID: environment.targetPID, prepareClipboard: {
            preparations += 1
            environment.clipboardChangeCount += 1
            return true
        }, beforeActivation: { dismissals += 1 }) {
            outcomes.append($0)
        }

        #expect(outcomes == [.permissionRequired])
        #expect(dismissals == 0)
        #expect(preparations == 0)
        #expect(environment.clipboardChangeCount == originalClipboardVersion)
        #expect(environment.activatedPIDs.isEmpty)
        #expect(environment.postAttempts == 0)
        #expect(environment.pendingCount == 0)
    }

    @Test func clipboardPreparationFailureDoesNotDismissActivateOrPost() {
        let environment = MockPasteEnvironment()
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        var preparations = 0
        var dismissals = 0

        service.paste(intoPID: environment.targetPID, prepareClipboard: {
            preparations += 1
            return false
        }, beforeActivation: { dismissals += 1 }) { outcomes.append($0) }
        environment.drain()

        #expect(outcomes == [.clipboardWriteFailed])
        #expect(preparations == 1)
        #expect(dismissals == 0)
        #expect(environment.activatedPIDs.isEmpty)
        #expect(environment.postAttempts == 0)
        #expect(environment.pendingCount == 0)
    }

    @Test func activationFailureStopsBeforeEventScheduling() {
        let environment = MockPasteEnvironment()
        environment.activationSucceeds = false
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }

        #expect(outcomes == [.targetUnavailable])
        #expect(service.diagnosticStage == "activate-target")
        #expect(environment.activatedPIDs == [environment.targetPID])
        #expect(environment.postAttempts == 0)
        #expect(environment.pendingCount == 0)
    }

    @Test func delayedActivationCanFinishBeforeTheDeadline() {
        let environment = MockPasteEnvironment()
        environment.frontmostPID = environment.ownPID
        environment.activationChangesFocus = false
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }

        #expect(environment.runNext())
        #expect(environment.postAttempts == 0)
        #expect(outcomes.isEmpty)
        environment.frontmostPID = environment.targetPID
        environment.drain()

        #expect(environment.postAttempts == 1)
        #expect(outcomes == [.eventPosted])
        #expect(environment.activatedPIDs.count == 1)
    }

    @Test func activationTimeoutIsBoundedAndNeverPosts() {
        for frontIsNil in [false, true] {
            let environment = MockPasteEnvironment()
            environment.frontmostPID = frontIsNil ? nil : environment.ownPID
            environment.activationChangesFocus = false
            let service = PasteService(environment: environment)
            var outcomes: [PasteService.Outcome] = []
            service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }
            environment.drain()

            #expect(outcomes == [.targetUnavailable])
            #expect(environment.postAttempts == 0)
            #expect(environment.activatedPIDs.count == 1)
            #expect(environment.pendingCount == 0)
            #expect(environment.elapsed < 5)
        }
    }

    @Test(arguments: WaitingPhase.allCases)
    func indefinitelyHeldKeysTimeOutWithoutPosting(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        var dismissals = 0
        service.paste(intoPID: environment.targetPID, beforeActivation: { dismissals += 1 }) {
            outcomes.append($0)
        }
        environment.keysAreReleased = false
        environment.drain()

        #expect(outcomes == [.keysStillPressed])
        #expect(environment.postAttempts == 0)
        #expect(dismissals == (phase == .restoringTarget ? 1 : 0))
        #expect(environment.pendingCount == 0)
        #expect(environment.elapsed < 5)
    }

    @Test func eventCreationOrPostingFailureIsReportedWithoutRetry() {
        let environment = MockPasteEnvironment()
        environment.postSucceeds = false
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }
        environment.drain()

        #expect(outcomes == [.targetUnavailable])
        #expect(service.diagnosticStage == "deliver-paste")
        #expect(environment.postAttempts == 1)
        #expect(environment.pendingCount == 0)
    }

    @Test func failedInputFocusRestorationStopsBeforeDeliveryAndIdentifiesStage() {
        let environment = MockPasteEnvironment()
        environment.restoresInputFocus = false
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []
        service.paste(intoPID: environment.targetPID, beforeActivation: {}) { outcomes.append($0) }
        environment.drain()

        #expect(outcomes == [.targetUnavailable])
        #expect(service.diagnosticStage == "restore-input-focus")
        #expect(environment.postAttempts == 0)
        #expect(environment.pendingCount == 0)
    }

    @Test(arguments: WaitingPhase.allCases)
    func aSecondSelectionReplacesTheFirstPendingOperation(_ phase: WaitingPhase) {
        let environment = MockPasteEnvironment()
        environment.keysAreReleased = phase == .restoringTarget
        let service = PasteService(environment: environment)
        var firstOutcomes: [PasteService.Outcome] = []
        var secondOutcomes: [PasteService.Outcome] = []
        var firstDismissals = 0
        var secondDismissals = 0
        service.paste(intoPID: environment.targetPID, beforeActivation: { firstDismissals += 1 }) {
            firstOutcomes.append($0)
        }

        environment.clipboardChangeCount += 1
        environment.keysAreReleased = true
        service.paste(intoPID: environment.targetPID, beforeActivation: { secondDismissals += 1 }) {
            secondOutcomes.append($0)
        }
        environment.drain()

        #expect(firstOutcomes.isEmpty)
        #expect(secondOutcomes == [.eventPosted])
        #expect(firstDismissals == (phase == .restoringTarget ? 1 : 0))
        #expect(secondDismissals == 1)
        #expect(environment.postAttempts == 1)
        #expect(environment.pendingCount == 0)
    }

    @Test func cancellationFromBeforeActivationDoesNotActivateTheOldTarget() {
        let environment = MockPasteEnvironment()
        let service = PasteService(environment: environment)
        var outcomes: [PasteService.Outcome] = []

        service.paste(intoPID: environment.targetPID, beforeActivation: { service.cancel() }) {
            outcomes.append($0)
        }
        environment.drain()

        #expect(environment.activatedPIDs.isEmpty)
        #expect(environment.postAttempts == 0)
        #expect(outcomes.isEmpty)
    }
}

// Each callback is run only when a test advances this clock. No AX APIs, actual
// applications, system pasteboards, DispatchQueue delays, or CGEvents are used.
private final class MockPasteEnvironment: PasteEnvironment {
    let targetPID: pid_t = 200
    let ownPID: pid_t = 100
    var hasPermission = true
    var frontmostPID: pid_t? = 200
    var clipboardChangeCount = 7
    var keysAreReleased = true
    var runningPIDs: Set<pid_t> = [200]
    var activationSucceeds = true
    var activationChangesFocus = true
    var postSucceeds = true
    var restoresInputFocus = true
    var trace: [String] = []
    private(set) var activatedPIDs: [pid_t] = []
    private(set) var postAttempts = 0
    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var elapsed: TimeInterval = 0
    private var nextOrder = 0
    private var jobs: [(deadline: TimeInterval, order: Int, action: () -> Void)] = []
    var pendingCount: Int { jobs.count }

    func isRunning(_ pid: pid_t) -> Bool { runningPIDs.contains(pid) }
    func restoreTargetFocus(_ pid: pid_t) -> Bool { restoresInputFocus }

    func activate(_ pid: pid_t) -> Bool {
        trace.append("activate")
        activatedPIDs.append(pid)
        if activationSucceeds && activationChangesFocus { frontmostPID = pid }
        return activationSucceeds
    }

    func postPasteShortcut() -> Bool {
        trace.append("post")
        postAttempts += 1
        return postSucceeds
    }

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        scheduledDelays.append(delay)
        jobs.append((elapsed + delay, nextOrder, action))
        nextOrder += 1
    }

    @discardableResult
    func runNext() -> Bool {
        guard !jobs.isEmpty else { return false }
        jobs.sort { ($0.deadline, $0.order) < ($1.deadline, $1.order) }
        let job = jobs.removeFirst()
        elapsed = job.deadline
        job.action()
        return true
    }

    func drain() {
        for _ in 0..<200 {
            if !runNext() { return }
        }
        Issue.record("Paste state machine did not finish within 200 scheduled callbacks")
    }
}
