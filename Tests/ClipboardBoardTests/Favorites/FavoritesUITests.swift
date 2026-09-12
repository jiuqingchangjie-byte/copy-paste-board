import AppKit
import Testing
import ClipboardCore
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct FavoritesUITests {
    private func descendants(_ view:NSView)->[NSView] { [view] + view.subviews.flatMap(descendants) }
    @Test func libraryCopyUsesTheSameLimitsAndSuppressesDuplicateCapture() {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName();defer { board.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard:board)
        let copy = PreviewCopyService(monitor:monitor)
        var saved:[HistoryEntry] = [], automatic = 0
        copy.onCopied = { saved.append($0) }
        monitor.onCapture = { _,_ in automatic += 1 }
        #expect(copy.copy(.text("favorite"),sourceName:"收藏库"))
        monitor.poll()
        #expect(saved.count == 1 && saved[0].sourceName == "收藏库" && automatic == 0)
        let count = board.changeCount
        #expect(!copy.copy(.image(Data(repeating:1,count:8*1024*1024+1)),sourceName:"收藏库"))
        #expect(board.changeCount == count && saved.count == 1)
    }
    @Test func historyOffersStarLibraryAndContextActionWithoutPasting() throws {
        _ = NSApplication.shared
        let history = HistoryPanelController()
        let entry = HistoryEntry(payload:.text("save me"))
        var favorites = 0, pasted = 0, opened = 0
        history.onFavorite = { _ in favorites += 1 }
        history.onOpenFavorites = { opened += 1 }
        history.onPaste = { _ in pasted += 1 }
        history.isFavorite = { _ in false }
        history.update(entries:[entry],paused:false)
        let root = try #require(history.window?.contentView);root.layoutSubtreeIfNeeded()
        let table = try #require(descendants(root).compactMap { $0 as? HistoryTableView }.first)
        let menu = try #require(table.contextMenuForRow?(0))
        #expect(menu.items.contains { $0.title == "收藏到未分类" })
        let cell = try #require(history.tableView(table,viewFor:table.tableColumns.first,row:0))
        let star = try #require(descendants(cell).compactMap { $0 as? NSButton }.first)
        star.performClick(nil)
        #expect(favorites == 1 && pasted == 0)
        let library = try #require(descendants(root).compactMap { $0 as? NSButton }.first { $0.title == "收藏" })
        library.performClick(nil)
        #expect(opened == 1)
    }
    @Test func libraryPagesMetadataAndEnablesBulkActionsOnlyWithSelection() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let repo = try FavoritesRepository(directoryURL:dir)
        for i in 0..<105 { try repo.add(HistoryEntry(payload:.text("favorite-\(i)"))) }
        let controller = FavoritesLibraryController()
        var copied = 0
        controller.onCopy = { _ in copied += 1; return true }
        defer { controller.close();repo.close() }
        controller.setRepository(repo)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        #expect(controller.content.entries.numberOfRows == 100)
        #expect(controller.content.search.frame.width > 550)
        #expect((controller.content.entries.enclosingScrollView?.frame.width ?? 0) > 550)
        #expect(controller.content.entries.allowsMultipleSelection)
        #expect(controller.content.next.isEnabled)
        controller.content.entries.selectRowIndexes(IndexSet([0,1,2]),byExtendingSelection:false)
        #expect(controller.content.remove.isEnabled && controller.content.move.isEnabled)
        #expect(!controller.content.copy.isEnabled && !controller.content.preview.isEnabled)
        controller.content.entries.copy(nil)
        #expect(copied == 0)
        controller.content.entries.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        #expect(controller.content.copy.isEnabled && controller.content.preview.isEnabled)
        controller.content.entries.copy(nil)
        #expect(copied == 1)
        controller.content.search.stringValue = "favorite-104"
        controller.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
        #expect(controller.content.entries.numberOfRows == 1)
        #expect(!controller.content.next.isEnabled)
        controller.setRepository(nil,message:"migration")
        #expect(!controller.content.clear.isEnabled && !controller.content.newFolder.isEnabled)
    }
}
