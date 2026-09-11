import AppKit
import Testing
import ClipboardCore
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct PreviewTests {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func event(_ code: UInt16, window: NSWindow, characters: String = " ", repeatKey: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code))
    }
    private func imageData() throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1200, height: 800)).fill()
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: NSRect(x: 150, y: 100, width: 500, height: 500)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func fullTextRetainsSQLJSONUnicodeAndCopiesOnlySelectedUTF16Range() throws {
        _ = NSApplication.shared
        let text = "SELECT *\nFROM demo;\r\n{\"城市\":\"杭州😀\"}\n" + String(repeating: "长文本\t原始换行\n", count: 2000)
        let content = TextPreviewViewController(text: text)
        _ = content.view
        content.view.layoutSubtreeIfNeeded()
        #expect(content.textView.string == text)
        #expect(content.textView.isSelectable && !content.textView.isEditable)
        #expect(content.scrollView.hasVerticalScroller)
        var copies: [String] = []
        content.onCopyText = { copies.append($0); return true }
        content.textView.copy(nil)
        #expect(copies.isEmpty)
        content.textView.setSelectedRange((text as NSString).range(of: "杭州😀"))
        content.textView.copy(nil)
        #expect(copies == ["杭州😀"])
        #expect(content.textView.string == text)
        content.textView.layoutManager?.ensureLayout(for: content.textView.textContainer!)
        #expect(content.textView.layoutManager!.usedRect(for: content.textView.textContainer!).height > content.scrollView.contentSize.height)
    }

    @Test func explicitCopyEntersBoundedHistoryOnceEvenWhenRecordingPaused() throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: board)
        let service = PreviewCopyService(monitor: monitor)
        var history = History(entries: [HistoryEntry(payload: .text("B")), HistoryEntry(payload: .text("A"))], maxCount: 2)
        var captures = 0
        monitor.onCapture = { _, _ in captures += 1 }
        service.onCopied = { history.insert($0) }
        #expect(service.copy("片段😀"))
        monitor.poll()
        #expect(captures == 0)
        #expect(history.entries.map(\.payload) == [.text("片段😀"), .text("B")])
        #expect(board.string(forType: .string) == "片段😀")
        #expect(service.copy("B"))
        #expect(history.entries.map(\.payload) == [.text("B"), .text("片段😀")])
        monitor.isPaused = true
        #expect(service.copy("手动复制"))
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.payload == .text("手动复制"))
        let count = board.changeCount
        #expect(!service.copy(""))
        #expect(!service.copy(String(repeating: "x", count: 8 * 1024 * 1024 + 1)))
        #expect(board.changeCount == count)
    }

    @Test func previewLifecycleNeverWritesClipboardOrPastesAndRestoresSelectionByID() throws {
        _ = NSApplication.shared
        let before = NSPasteboard.general.changeCount
        let controller = HistoryPanelController()
        defer { controller.dismiss(); controller.previews.closeAll() }
        let entries = [HistoryEntry(payload: .text("first")), HistoryEntry(payload: .text("second\nfull"))]
        controller.present(entries: entries, hasPermission: true, paused: false)
        let panel = try #require(controller.window as? KeyboardPanel)
        let table = try #require(descendants(panel.contentView!).compactMap { $0 as? NSTableView }.first)
        panel.makeFirstResponder(table)
        var pasted = 0
        controller.onPaste = { _ in pasted += 1 }
        controller.showPreview(row: 1, takeFocus: true)
        let preview = try #require(controller.previews.transient?.window as? PreviewPanel)
        #expect(table.selectedRow == 0)
        #expect(controller.isVisible)
        #expect(preview.isVisible)
        #expect(panel.performKeyEquivalent(with: try event(36, window: panel, characters: "\r")))
        panel.onAccept?()
        #expect(pasted == 0)
        let newer = HistoryEntry(payload: .text("new"))
        controller.update(entries: [newer] + entries, paused: false)
        #expect(preview.performKeyEquivalent(with: try event(53, window: preview, characters: "\u{1b}")))
        #expect(!controller.previews.isPreviewing)
        #expect(table.selectedRow == 1)
        #expect(panel.firstResponder === table)
        #expect(NSPasteboard.general.changeCount == before)
        panel.onAccept?()
        #expect(pasted == 1)
    }

    @Test func spaceIsOnlyPreviewShortcutOutsideTextEditingAndIME() throws {
        _ = NSApplication.shared
        let panel = KeyboardPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        var previews = 0
        panel.onPreview = { previews += 1 }
        let table = NSTableView(frame: panel.contentView!.bounds)
        panel.contentView?.addSubview(table)
        panel.makeFirstResponder(table)
        #expect(panel.performKeyEquivalent(with: try event(49, window: panel)))
        #expect(previews == 1)
        #expect(panel.performKeyEquivalent(with: try event(49, window: panel, repeatKey: true)))
        #expect(previews == 1)
        let editor = NSTextView(frame: table.bounds)
        panel.contentView?.addSubview(editor)
        panel.makeFirstResponder(editor)
        _ = panel.performKeyEquivalent(with: try event(49, window: panel))
        #expect(previews == 1)
        panel.sendEvent(try event(49, window: panel))
        #expect(editor.string == " ")
    }

    @Test func imageZoomPinDetachDragAndClosePreserveClipboard() throws {
        _ = NSApplication.shared
        let before = NSPasteboard.general.changeCount
        let parent = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 490),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let coordinator = HistoryPreviewCoordinator()
        defer { coordinator.closeAll(); parent.orderOut(nil) }
        coordinator.show(entry: HistoryEntry(payload: .image(try imageData())),
            anchor: NSRect(x: 100, y: 300, width: 200, height: 80), parent: parent, takeFocus: false)
        let controller = try #require(coordinator.transient)
        let image = try #require(controller.contentController as? ImagePreviewViewController)
        let window = try #require(controller.window)
        #expect(window.parent === parent)
        #expect(image.imageView.image?.size == NSSize(width: 1200, height: 800))
        #expect(image.scrollView.magnification < 1)
        #expect(image.scrollView.magnification > 0.1)
        #expect(image.scrollView.frame.width == image.view.bounds.width)
        #expect(image.scrollView.contentSize.height >= 100)
        let handle = try #require(descendants(window.contentView!).first { $0.toolTip == "拖动这里移动预览" })
        let hint = try #require(descendants(handle).compactMap { $0 as? NSTextField }.first)
        let hintPoint = hint.convert(NSPoint(x: hint.bounds.midX, y: hint.bounds.midY), to: handle.superview)
        #expect(handle.hitTest(hintPoint) === handle)
        let pin = try #require(descendants(handle).compactMap { $0 as? NSButton }.first)
        let pinPoint = pin.convert(NSPoint(x: pin.bounds.midX, y: pin.bounds.midY), to: handle.superview)
        #expect(handle.hitTest(pinPoint) === pin)
        image.actualSize()
        #expect(image.scrollView.magnification == 1)
        image.zoomIn()
        #expect(image.scrollView.magnification > 1)
        image.setZoom(100)
        #expect(image.scrollView.magnification == 8)
        controller.togglePin()
        #expect(controller.isPinned && coordinator.detached.count == 1)
        #expect(coordinator.transient == nil && window.parent == nil)
        #expect(window.level == .floating && window.isMovable)
        parent.orderOut(nil)
        coordinator.closeTransient(restoreSelection: false)
        #expect(window.isVisible)
        let position = NSPoint(x: 160, y: 220)
        window.setFrameOrigin(position)
        #expect(window.frame.origin == position)
        controller.togglePin()
        #expect(window.level == .normal && !controller.isPinned)
        controller.requestClose()
        #expect(coordinator.detached.isEmpty && !window.isVisible)
        #expect(NSPasteboard.general.changeCount == before)
    }

    @Test func previewPlacementStaysInsideNegativeOriginAndSmallScreens() {
        for screen in [NSRect(x: -1440, y: 0, width: 1440, height: 850), NSRect(x: 0, y: 0, width: 400, height: 300)] {
            for anchor in [NSRect(x: screen.maxX - 200, y: screen.maxY - 80, width: 190, height: 80),
                           NSRect(x: screen.minX, y: screen.minY, width: 190, height: 80)] {
                let frame = EntryPreviewWindowController.anchoredFrame(size: NSSize(width: 560, height: 450), anchor: anchor, visibleFrame: screen)
                #expect(screen.contains(frame))
            }
        }
    }

    @Test func hoverDelayCancelsStaleRowsAndDoesNotRestartInsideSameRow() {
        let scheduler = HoverPreviewScheduler()
        var shown: [String] = []
        let first = UUID()
        scheduler.schedule(id: first, delay: 0.03) { shown.append("first") }
        scheduler.schedule(id: first, delay: 5) { shown.append("wrong") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        #expect(shown == ["first"])
        scheduler.schedule(id: UUID(), delay: 0.03) { shown.append("cancelled") }
        scheduler.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        #expect(shown == ["first"])
        scheduler.schedule(id: UUID(), delay: 0.03) { shown.append("stale") }
        scheduler.schedule(id: UUID(), delay: 0.03) { shown.append("latest") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        #expect(shown == ["first", "latest"])
    }

    @Test func pointerHoverHonorsPreferencesAndDoesNotTakeFocusOrSelection() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        defer { controller.dismiss(); controller.previews.closeAll() }
        let entries = [HistoryEntry(payload: .text("selected")), HistoryEntry(payload: .text("hovered\nfull"))]
        controller.present(entries: entries, hasPermission: true, paused: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let panel = try #require(controller.window as? KeyboardPanel)
        let table = try #require(descendants(panel.contentView!).compactMap { $0 as? HistoryTableView }.first)
        let originalResponder = panel.firstResponder
        let before = NSPasteboard.general.changeCount
        #expect(panel.acceptsMouseMovedEvents)
        controller.previewSettings = PreviewSettings(hoverEnabled: false, hoverDelay: 0.2)
        table.onHoverRow?(1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        #expect(!controller.previews.isPreviewing)
        controller.previewSettings = PreviewSettings(hoverDelay: 0.2)
        table.onHoverRow?(1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(!controller.previews.isPreviewing)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        #expect(controller.previews.transient?.entryID == entries[1].id)
        #expect(panel.firstResponder === originalResponder)
        #expect(table.selectedRow == 0)
        #expect(NSPasteboard.general.changeCount == before)
        controller.previews.closeTransient(restoreSelection: true)
        table.onHoverRow?(1)
        table.onCancelHover?()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        #expect(!controller.previews.isPreviewing)
    }

    @Test func imageContextMenuTargetsHoveredItemWithoutChangingSelectionOrPasting() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        defer { controller.previews.closeAll() }
        let entries = [HistoryEntry(payload: .text("text")), HistoryEntry(payload: .image(try imageData()))]
        controller.update(entries: entries, paused: false)
        let table = try #require(descendants(controller.window!.contentView!).compactMap { $0 as? HistoryTableView }.first)
        let menu = try #require(table.contextMenuForRow?(1))
        let item = try #require(menu.items.first)
        #expect(item.title == "查看原图")
        #expect(item.representedObject as? UUID == entries[1].id)
        #expect(table.selectedRow == 0)
        #expect(table.contextMenuForRow?(-1) == nil)
    }

    @Test func invalidImageDoesNotOpenAndDeletingSourceClosesTransientOnly() throws {
        _ = NSApplication.shared
        let controller = HistoryPanelController()
        defer { controller.previews.closeAll() }
        let bad = HistoryEntry(payload: .image(Data([0, 1, 2])))
        let text = HistoryEntry(payload: .text("source"))
        controller.update(entries: [bad, text], paused: false)
        controller.showPreview(row: 0, takeFocus: false)
        #expect(!controller.previews.isPreviewing)
        controller.showPreview(row: 1, takeFocus: false)
        #expect(controller.previews.isPreviewing)
        controller.update(entries: [], paused: false)
        #expect(!controller.previews.isPreviewing)
    }
}
