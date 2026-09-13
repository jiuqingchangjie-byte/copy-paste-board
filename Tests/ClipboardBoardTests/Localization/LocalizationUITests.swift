import AppKit
import Foundation
import Testing
import ClipboardCore
@testable import ClipboardBoard

// Run separately because language is process-wide and other suites assert Chinese labels.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CLIPBOARDBOARD_LOCALIZATION_UI"] == "1"))
@MainActor
struct LocalizationUITests {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func verifyAndCapture(_ window: NSWindow, name: String) throws {
        let root = try #require(window.contentView)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.layoutSubtreeIfNeeded()
        for button in descendants(root).compactMap({ $0 as? NSButton }) where !button.isHidden && !button.title.isEmpty {
            #expect(button.frame.width + 2 >= button.fittingSize.width, "\(name): \(button.title) width \(button.frame.width) < \(button.fittingSize.width)")
        }
        if let path = ProcessInfo.processInfo.environment["CLIPBOARDBOARD_LOCALIZATION_CAPTURES"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rep = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
    @Test func fourLanguageViewsKeepActionsAndUserContentIntact() throws {
        _ = NSApplication.shared
        let originalLanguage = L10n.language
        defer { L10n.language = originalLanguage }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try FavoritesRepository(directoryURL: root)
        defer { repo.close() }
        let text = "ClipboardBoard language test\n原文保留 · 日本語 · 한국어 · 100% {1}"
        let entry = HistoryEntry(payload: .text(text), sourceName: "Example App")
        let folder = "My folder 日本語 한국어"
        try repo.createFolder(name: folder)
        try repo.add(entry)
        let library = FavoritesLibraryController()
        defer { library.close() }
        library.setRepository(repo)
        for language in AppLanguage.allCases {
            L10n.language = language
            let prefix = language.rawValue
            let history = HistoryPanelController()
            history.update(entries: [entry], paused: false)
            history.updatePermission(false)
            defer { history.close() }
            #expect(history.window?.title == L10n.tr("剪贴板历史"))
            let historyRoot = try #require(history.window?.contentView)
            let search = try #require(descendants(historyRoot).compactMap { $0 as? NSSearchField }.first)
            #expect(search.placeholderString == L10n.tr("搜索内容或来源应用"))
            try verifyAndCapture(try #require(history.window), name: prefix + "-history")
            #expect(history.window?.frame.size == NSSize(width: 340, height: 490))
            let list = try #require(descendants(historyRoot).compactMap { $0 as? NSScrollView }.first)
            #expect(list.frame.width == 304)
            let footer = try #require(descendants(historyRoot).compactMap { $0 as? NSTextField }
                .first { $0.stringValue == L10n.tr("↑ ↓ 选择   空格预览   ↩ 粘贴   esc 关闭") })
            #expect(footer.alignmentRect(forFrame: footer.frame).width == 304)
            for button in descendants(historyRoot).compactMap({ $0 as? NSButton }) where !button.isHidden {
                let bounds = button.convert(button.bounds, to: historyRoot)
                #expect(bounds.minX >= 0 && bounds.maxX <= 340, "\(prefix): \(button.title) outside compact panel")
            }
            var pasted: HistoryEntry?
            history.onPaste = { pasted = $0 }
            (history.window as? KeyboardPanel)?.onAccept?()
            #expect(pasted?.payload == entry.payload)
            history.update(entries: [], paused: true)
            try verifyAndCapture(try #require(history.window), name: prefix + "-history-empty")
            #expect(history.window?.frame.size == NSSize(width: 340, height: 490))
            library.content.entries.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            library.refreshLanguage()
            #expect(library.content.entries.numberOfRows == 1)
            #expect(library.content.entries.selectedRow == 0)
            #expect(library.content.heading.stringValue == L10n.tr("全部收藏"))
            #expect(library.content.copy.title == L10n.tr("复制内容"))
            #expect(try repo.folders().first?.name == folder)
            #expect(try repo.entry(id: repo.page().items[0].id)?.payload == entry.payload)
            try verifyAndCapture(try #require(library.window), name: prefix + "-favorites")
            let preview = try #require(EntryPreviewWindowController(entry: entry, onCopyText: { _ in true }))
            defer { preview.close() }
            #expect((preview.contentController as? TextPreviewViewController)?.textView.string == text)
            try verifyAndCapture(try #require(preview.window), name: prefix + "-preview")
            let shortcuts = ShortcutPreferencesController()
            defer { shortcuts.close() }
            #expect(shortcuts.window?.title == L10n.tr("自定义快捷键"))
            try verifyAndCapture(try #require(shortcuts.window), name: prefix + "-shortcut")
            let storage = StoragePreferencesController()
            defer { storage.close() }
            #expect(storage.window?.title == L10n.tr("存储位置"))
            try verifyAndCapture(try #require(storage.window), name: prefix + "-storage")
            let keypad = KeyboardShortcut(keyCode: 82, modifiers: .command)
            #expect(keypad.displayName == "⌘" + L10n.tr("小键盘 {0}", "0"))
            do { _ = try JSONTextFormatter.format("{") }
            catch { #expect(error.localizedDescription.contains(L10n.tr("对象键必须使用双引号"))) }
        }
    }
}
