import Carbon
import ClipboardCore

protocol HotKeyBackend: AnyObject {
    var onEvent: ((UInt32) -> Void)? { get set }
    func acquire(_ shortcut: KeyboardShortcut, id: UInt32) throws
    func release(id: UInt32)
}

/// One Carbon handler, uniquely identified registrations, and explicit lifetimes.
final class CarbonHotKeyBackend: HotKeyBackend {
    static let signature: OSType = 0x434C5042
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var pressedIDs = Set<UInt32>()
    var onEvent: ((UInt32) -> Void)?

    func acquire(_ shortcut: KeyboardShortcut, id: UInt32) throws {
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == CarbonHotKeyBackend.signature else { return OSStatus(eventNotHandledErr) }
                Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
                    .receive(id: id.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
                return noErr
            }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw ShortcutError(message: L10n.tr("无法安装快捷键事件处理器（{0}）。", String(describing: status))) }
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else {
            throw ShortcutError(message: L10n.tr("{0} 注册失败，可能被其他应用占用（{1}）。请换一个组合。", String(describing: shortcut.displayName), String(describing: status)))
        }
        references[id] = reference
    }

    func release(id: UInt32) {
        pressedIDs.remove(id)
        guard let reference = references.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reference)
    }

    func receive(id: UInt32, pressed: Bool) {
        guard references[id] != nil else { return }
        if pressed {
            if pressedIDs.insert(id).inserted { onEvent?(id) }
        } else { pressedIDs.remove(id) }
    }

    deinit {
        references.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
