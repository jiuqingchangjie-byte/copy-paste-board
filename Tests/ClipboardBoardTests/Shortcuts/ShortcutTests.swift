import AppKit
import Carbon
import Testing
import ClipboardCore
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct ShortcutTests {
    final class FakeBackend: HotKeyBackend {
        var onEvent: ((UInt32) -> Void)?
        var registrations: [UInt32: KeyboardShortcut] = [:]
        var fail = false
        var acquisitions = 0
        func acquire(_ shortcut: KeyboardShortcut, id: UInt32) throws {
            if fail { throw ShortcutError(message: "occupied") }
            acquisitions += 1
            registrations[id] = shortcut
        }
        func release(id: UInt32) { registrations.removeValue(forKey: id) }
    }
    let custom = KeyboardShortcut(keyCode: 40, modifiers: [.control,.option,.command])

    @Test func switchIsTransactionalAndStaleEventsCannotInvokeAction() throws {
        let backend = FakeBackend()
        let service = GlobalHotKey(backend: backend, checkSystem: { _ in })
        try service.set(.default)
        var calls = 0
        service.onPress = { calls += 1 }
        var stored = KeyboardShortcut.default
        try service.set(custom) {
            #expect(backend.registrations.count == 2)
            backend.onEvent?(2) // Candidate cannot toggle history before commit.
            #expect(calls == 0)
            stored = custom
        }
        #expect(stored == custom && service.activeShortcut == custom)
        #expect(backend.registrations == [2:custom])
        backend.onEvent?(1)
        backend.onEvent?(2)
        #expect(calls == 1)
        try service.set(custom)
        #expect(backend.acquisitions == 2)
    }

    @Test func conflictAndSaveFailureKeepOldRegistrationAndStoredSetting() throws {
        let backend = FakeBackend()
        let service = GlobalHotKey(backend: backend, checkSystem: { _ in })
        try service.set(.default)
        backend.fail = true
        var saved = false
        #expect(throws: (any Error).self) { try service.set(custom) { saved = true } }
        #expect(!saved && backend.registrations == [1:.default])
        backend.fail = false
        #expect(throws: (any Error).self) { try service.set(custom) { throw CocoaError(.fileWriteNoPermission) } }
        #expect(backend.registrations == [1:.default] && service.activeShortcut == .default)
        var calls = 0
        service.onPress = { calls += 1 }
        backend.onEvent?(1)
        #expect(calls == 1)
    }

    @Test func systemConflictAndInvalidInputDoNotReachBackendOrPersistence() throws {
        let backend = FakeBackend()
        let service = GlobalHotKey(backend: backend, checkSystem: { _ in throw ShortcutError(message: "system conflict") })
        #expect(throws: (any Error).self) { try service.set(custom) }
        #expect(throws: (any Error).self) { try service.set(KeyboardShortcut(keyCode: 8, modifiers: .command)) }
        #expect(backend.acquisitions == 0 && service.activeShortcut == nil)
    }

    @Test func actualCarbonConflictsReleaseOldKeysAndReuseSingleHandler() throws {
        _ = NSApplication.shared
        // Rare combination, independent of the user's running Option-V owner.
        let a = KeyboardShortcut(keyCode: 98, modifiers: [.control,.option,.command,.shift])
        let b = KeyboardShortcut(keyCode: 100, modifiers: [.control,.option,.command,.shift])
        let backend = CarbonHotKeyBackend()
        let other = CarbonHotKeyBackend()
        try backend.acquire(a, id: 701)
        defer { backend.release(id: 701); backend.release(id: 702); other.release(id: 801) }
        #expect(throws: (any Error).self) { try other.acquire(a, id: 801) }
        try backend.acquire(b, id: 702)
        backend.release(id: 701)
        try other.acquire(a, id: 801)
        var calls = 0
        backend.onEvent = { _ in calls += 1 }
        backend.receive(id: 702, pressed: true)
        backend.receive(id: 702, pressed: true)
        backend.receive(id: 702, pressed: false)
        backend.receive(id: 702, pressed: true)
        backend.receive(id: 701, pressed: true)
        #expect(calls == 2)
    }

    @Test func actualSystemShortcutListCanBeRead() throws {
        _ = NSApplication.shared
        // Read the real system list; conflict checking itself never grabs a key.
        try ShortcutConflictPolicy.checkSystem(custom)
        #expect(custom.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test func installedCarbonHandlerRoutesPressReleaseToActiveCallback() throws {
        _ = NSApplication.shared
        let service = GlobalHotKey(checkSystem: { _ in })
        try service.set(KeyboardShortcut(keyCode: 111, modifiers: [.control,.option,.command,.shift]))
        var calls = 0
        service.onPress = { calls += 1 }
        func send(_ kind: Int, id: UInt32 = 1) throws {
            var event: EventRef?
            #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), 0, 0, &event) == noErr)
            let created = try #require(event)
            defer { ReleaseEvent(created) }
            var hotKeyID = EventHotKeyID(signature: CarbonHotKeyBackend.signature, id: id)
            #expect(SetEventParameter(created, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &hotKeyID) == noErr)
            #expect(SendEventToEventTarget(created, GetApplicationEventTarget()) == noErr)
        }
        try send(kEventHotKeyPressed)
        try send(kEventHotKeyPressed)
        try send(kEventHotKeyReleased)
        try send(kEventHotKeyPressed)
        try send(kEventHotKeyPressed, id: 99)
        #expect(calls == 2)
    }

    @Test func otherProcessExclusiveRegistrationIsDetectedBeforeTakingOver() throws {
        _ = NSApplication.shared
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-e", """
        import AppKit
        import Carbon
        _ = NSApplication.shared
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(97, UInt32(controlKey | optionKey | cmdKey | shiftKey),
            EventHotKeyID(signature: 0x54455354, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        FileHandle.standardOutput.write(Data([status == noErr ? UInt8(1) : UInt8(0)]))
        _ = FileHandle.standardInput.readData(ofLength: 1)
        if let ref { UnregisterEventHotKey(ref) }
        """]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer {
            input.fileHandleForWriting.write(Data([1]))
            process.waitUntilExit()
        }
        #expect(output.fileHandleForReading.readData(ofLength: 1) == Data([1]))
        let backend = CarbonHotKeyBackend()
        #expect(throws: (any Error).self) {
            try backend.acquire(KeyboardShortcut(keyCode: 97, modifiers: [.control,.option,.command,.shift]), id: 900)
        }
        backend.release(id: 900)
    }

    @Test func recorderCapturesModifiersAndProtectsReturnEscapeAndEditingCommands() throws {
        _ = NSApplication.shared
        let editor = ShortcutPreferencesController()
        defer { editor.close() }
        let recorder = editor.recorder
        let window = try #require(editor.window as? ShortcutPreferencesWindow)
        func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: repeatKey, keyCode: code))
        }
        var saves = 0
        editor.present(current: .default, isRegistered: true) { _ in saves += 1 }
        editor.beginRecording()
        #expect(window.performKeyEquivalent(with: try event(36)))
        #expect(recorder.isRecording && saves == 0)
        #expect(window.performKeyEquivalent(with: try event(12, .command))) // Cmd-Q must not quit while recording.
        #expect(recorder.isRecording && recorder.shortcut == .default)
        #expect(window.performKeyEquivalent(with: try event(40, [.control,.option,.command], repeatKey: true)))
        #expect(recorder.shortcut == .default)
        #expect(window.performKeyEquivalent(with: try event(40, [.control,.option,.command,.capsLock])))
        #expect(recorder.shortcut == custom && !recorder.isRecording)
        editor.beginRecording()
        #expect(window.performKeyEquivalent(with: try event(53)))
        #expect(!recorder.isRecording && recorder.shortcut == custom && editor.isVisible)
        editor.restoreDefault()
        #expect(recorder.shortcut == .default && saves == 0)
        editor.saveShortcut()
        #expect(saves == 1 && !editor.isVisible)
    }

    @Test func failedSaveStaysEditableAndRegisteredShortcutCanBeRecorded() {
        _ = NSApplication.shared
        let editor = ShortcutPreferencesController()
        defer { editor.close() }
        editor.present(current: custom, isRegistered: true) { _ in throw CocoaError(.fileWriteNoPermission) }
        editor.beginRecording()
        editor.receiveRegisteredShortcut(custom)
        #expect(editor.recorder.shortcut == custom && !editor.recorder.isRecording)
        editor.saveShortcut()
        #expect(editor.isVisible)
        editor.cancelEditing()
        #expect(!editor.isVisible)
    }

    @Test func serviceLifetimeReleasesItsRegistration() throws {
        let backend = FakeBackend()
        var service: GlobalHotKey? = GlobalHotKey(backend: backend, checkSystem: { _ in })
        try service?.set(custom)
        service = nil
        #expect(backend.registrations.isEmpty)
    }
}
