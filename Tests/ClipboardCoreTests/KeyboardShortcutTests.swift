import Foundation
import Testing
@testable import ClipboardCore

struct KeyboardShortcutTests {
    @Test func legacySettingsDefaultAndCustomizedSettingsRoundTrip() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"maxHistoryCount":25,"hasLaunched":true}"#.utf8))
        #expect(old.shortcut == .default)
        let custom = KeyboardShortcut(keyCode: 40, modifiers: [.control,.option,.shift,.command])
        var next = old
        next.shortcut = custom
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(next)) == next)
        #expect(custom.displayName == "⌃⌥⇧⌘K")
    }
    @Test func invalidStoredCombinationsFallBackWithoutDiscardingOtherSettings() throws {
        for shortcut in [KeyboardShortcut(keyCode: 999, modifiers: .option),
                         KeyboardShortcut(keyCode: 9, modifiers: .shift),
                         KeyboardShortcut(keyCode: 9, modifiers: .init(rawValue: 128))] {
            var settings = AppSettings(maxHistoryCount: 23)
            settings.shortcut = shortcut
            let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            #expect(loaded.shortcut == .default && loaded.maxHistoryCount == 23)
        }
    }
}
