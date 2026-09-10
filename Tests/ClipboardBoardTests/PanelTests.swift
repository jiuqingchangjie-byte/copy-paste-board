import AppKit
import Testing
import ClipboardCore
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct PanelTests {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @Test func returnAndKeypadEnterUseAppKitKeyEquivalentRouteOnce() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        let entries = [HistoryEntry(payload: .text("first")), HistoryEntry(payload: .text("second"))]
        controller.update(entries: entries, paused: false)
        let panel = try #require(controller.window as? KeyboardPanel)
        var accepted: [UUID] = []
        controller.onPaste = { accepted.append($0.id) }
        for code: UInt16 in [36, 76] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: Double(code), windowNumber: panel.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code))
            #expect(panel.performKeyEquivalent(with: event))
        }
        #expect(accepted == [entries[0].id, entries[0].id])
        let repeated = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 100, windowNumber: panel.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: true, keyCode: 36))
        #expect(panel.performKeyEquivalent(with: repeated))
        #expect(accepted.count == 2)
    }

    private final class ComposingTextView: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }

    @Test func searchFieldReturnCommandPastesSelectedRecordAndRespectsIME() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        let entries = [HistoryEntry(payload: .text("first")), HistoryEntry(payload: .text("second"))]
        controller.update(entries: entries, paused: false)
        let root = try #require(controller.window?.contentView)
        let search = try #require(descendants(root).compactMap { $0 as? NSSearchField }.first)
        var accepted: [UUID] = []
        controller.onPaste = { accepted.append($0.id) }
        let editor = NSTextView()
        #expect(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(accepted == [entries[1].id])
        #expect(!controller.control(search, textView: ComposingTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(accepted.count == 1)
        controller.update(entries: [], paused: false)
        #expect(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(accepted.count == 1)
    }

    @Test func selectionBoundariesSearchDeletionAndEmptyHistory() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        let entries = [HistoryEntry(payload: .text("第一条")), HistoryEntry(payload: .text("second"))]
        controller.update(entries: entries, paused: false)
        let panel = try #require(controller.window as? KeyboardPanel)
        let views = descendants(try #require(panel.contentView))
        let table = try #require(views.compactMap { $0 as? NSTableView }.first)
        let search = try #require(views.compactMap { $0 as? NSSearchField }.first)
        var accepted: HistoryEntry?
        controller.onPaste = { accepted = $0 }
        #expect(table.numberOfRows == 2)
        #expect(table.selectedRow == 0)
        panel.onMove?(-1)
        #expect(table.selectedRow == 0)
        panel.onMove?(1)
        panel.onMove?(1)
        #expect(table.selectedRow == 1)
        panel.onAccept?()
        #expect(accepted == entries[1])
        var removed: UUID?
        controller.onDeleteEntry = { removed = $0 }
        panel.onDelete?()
        #expect(removed == entries[1].id)
        search.stringValue = "第一"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(table.numberOfRows == 1)
        panel.onAccept?()
        #expect(accepted == entries[0])
        controller.update(entries: [], paused: false)
        accepted = nil
        panel.onMove?(1)
        panel.onAccept?()
        #expect(table.numberOfRows == 0)
        #expect(accepted == nil)
    }

    @Test func textAndImageLayoutInLightAndDarkAppearance() throws {
        _ = NSApplication.shared
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 60,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<160 { for y in 0..<60 {
            bitmap.setColor(NSColor(calibratedRed: CGFloat(x) / 200 + 0.15,
                                    green: CGFloat(y) / 100 + 0.2, blue: 0.85, alpha: 1), atX: x, y: y)
        } }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let entries = [
            HistoryEntry(payload: .text("让每一次复制，都能轻松找回。"), sourceName: "文本编辑"),
            HistoryEntry(payload: .image(png), sourceName: "预览"),
            HistoryEntry(payload: .text("会议笔记\n完成界面设计，确认文字与图片的复制体验。"), sourceName: "备忘录"),
            HistoryEntry(payload: .text("https://example.com/design"), sourceName: "Safari")
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let controller = HistoryPanelController()
            let root = try #require(controller.window?.contentView)
            root.appearance = NSAppearance(named: name)
            controller.updatePermission(true)
            controller.update(entries: entries, paused: false)
            root.layoutSubtreeIfNeeded()
            let table = try #require(descendants(root).compactMap { $0 as? NSTableView }.first)
            #expect(table.numberOfRows == 4)
            #expect(table.frame.width > 300)
            #expect(table.rect(ofRow: 1).height > table.rect(ofRow: 0).height)
            #expect(!(root.hasAmbiguousLayout))
            #expect(root.bounds.width == 340)
            let representation = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: representation)
            // The corners must be transparent, including the material behind the content.
            for (x, y) in [(0, 0), (representation.pixelsWide - 1, 0),
                           (0, representation.pixelsHigh - 1),
                           (representation.pixelsWide - 1, representation.pixelsHigh - 1)] {
                let color = try #require(representation.colorAt(x: x, y: y))
                #expect(color.alphaComponent == 0)
            }
            let header = try #require(descendants(root).first { $0.toolTip == "拖动这里移动剪贴板" })
            let clear = try #require(descendants(header).compactMap { $0 as? NSButton }.first { $0.title == "全部清空" })
            let clearPoint = clear.convert(NSPoint(x: clear.bounds.midX, y: clear.bounds.midY), to: header.superview)
            #expect(header.hitTest(clearPoint) === clear)
            let title = try #require(descendants(header).compactMap { $0 as? NSTextField }.first { $0.stringValue == "剪贴板" })
            let titlePoint = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: header.superview)
            #expect(header.hitTest(titlePoint) === header)
            if let directory = ProcessInfo.processInfo.environment["CLIPBOARD_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let output = try #require(representation.representation(using: .png, properties: [:]))
                try output.write(to: url.appendingPathComponent(name == .aqua ? "light.png" : "dark.png"))
            }
        }
    }

    @Test func doubleClickUsesClickedItemWithNoPriorSelection() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        let entries = [HistoryEntry(payload: .text("first")), HistoryEntry(payload: .text("second"))]
        controller.update(entries: entries, paused: false)
        let root = try #require(controller.window?.contentView)
        let table = try #require(descendants(root)
            .compactMap { $0 as? NSTableView }.first)
        table.allowsEmptySelection = true
        table.deselectAll(nil)
        #expect(table.selectedRow == -1)
        var accepted: [HistoryEntry] = []
        controller.onPaste = { accepted.append($0) }
        controller.useClickedRow(1)
        #expect(accepted == [entries[1]])
        #expect(table.selectedRow == 1)
        controller.useClickedRow(0)
        #expect(accepted == [entries[1], entries[0]])
        controller.useClickedRow(-1)
        controller.useClickedRow(9)
        #expect(accepted.count == 2)
    }
}
