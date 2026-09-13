import ClipboardCore

/// Reserve the candidate first; only switch routing after persistence succeeds.
/// The old registration remains live throughout validation and failed saves.
final class GlobalHotKey {
    private let backend: HotKeyBackend
    private let checkSystem: (KeyboardShortcut) throws -> Void
    private var nextID: UInt32 = 0
    private(set) var activeShortcut: KeyboardShortcut?
    private var activeID: UInt32?
    var onPress: (() -> Void)?

    init(backend: HotKeyBackend = CarbonHotKeyBackend(),
         checkSystem: @escaping (KeyboardShortcut) throws -> Void = ShortcutConflictPolicy.checkSystem) {
        self.backend = backend
        self.checkSystem = checkSystem
        backend.onEvent = { [weak self] id in
            guard let self, id == self.activeID else { return }
            self.onPress?()
        }
    }

    func set(_ shortcut: KeyboardShortcut, persist: () throws -> Void = {}) throws {
        try ShortcutConflictPolicy.validate(shortcut)
        if activeShortcut == shortcut { try persist(); return }
        try checkSystem(shortcut)
        nextID += 1
        let candidateID = nextID
        try backend.acquire(shortcut, id: candidateID)
        do { try persist() }
        catch {
            backend.release(id: candidateID)
            throw ShortcutError(message: L10n.tr("保存失败，原快捷键保持不变。请检查数据目录或通过“数据与恢复”重试。"))
        }
        let oldID = activeID
        activeID = candidateID
        activeShortcut = shortcut
        if let oldID { backend.release(id: oldID) }
    }

    deinit { if let activeID { backend.release(id: activeID) } }
}
