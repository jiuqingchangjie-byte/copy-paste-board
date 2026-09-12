import Carbon
import ClipboardCore

struct ShortcutError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ShortcutConflictPolicy {
    static func validate(_ shortcut: KeyboardShortcut) throws {
        guard shortcut.isValid else { throw ShortcutError(message: "请使用 ⌘、⌥、⌃ 中至少一个修饰键，加字母、数字或功能键。") }
        // Do not turn ubiquitous app editing/window commands into global grabs.
        if shortcut.modifiers == .command, [0,6,7,8,9,12,13,46,48,49].contains(shortcut.keyCode) {
            throw ShortcutError(message: "\(shortcut.displayName) 是常用编辑或系统快捷键，请换一个组合。")
        }
        if shortcut.modifiers == [.command, .shift], [6,48].contains(shortcut.keyCode) {
            throw ShortcutError(message: "\(shortcut.displayName) 是常用编辑或系统快捷键，请换一个组合。")
        }
    }

    static func checkSystem(_ shortcut: KeyboardShortcut) throws {
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        guard status == noErr, let values = array?.takeRetainedValue() as? [[String: Any]] else {
            throw ShortcutError(message: "无法检查系统快捷键（\(status)），请重试。原快捷键保持不变。")
        }
        for value in values {
            if (value[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
               (value[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode,
               (value[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.carbonModifiers {
                throw ShortcutError(message: "\(shortcut.displayName) 已被系统快捷键占用，请换一个组合。")
            }
        }
    }
}

extension KeyboardShortcut {
    var carbonModifiers: UInt32 {
        (modifiers.contains(.command) ? UInt32(cmdKey) : 0)
        | (modifiers.contains(.option) ? UInt32(optionKey) : 0)
        | (modifiers.contains(.control) ? UInt32(controlKey) : 0)
        | (modifiers.contains(.shift) ? UInt32(shiftKey) : 0)
    }
}
