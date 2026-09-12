import AppKit
import Testing
import ClipboardCore
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
struct JSONPreviewTests {
    private func awaitFormatting(_ controller: JSONPreviewFormattingController) async throws {
        let deadline = Date().addingTimeInterval(10)
        while controller.isFormatting && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isFormatting)
    }

    @Test func buttonFormatsFullTextAndRestoresExactOriginalWithoutWrites() async throws {
        _ = NSApplication.shared
        let original = " \r\n{\"id\":900719925474099312345,\"list\":[1,2],\"s\":\"杭州😀\"}\t "
        let preview = TextPreviewViewController(text: original)
        _ = preview.view
        let controls = try #require(preview.formatting)
        let count = NSPasteboard.general.changeCount
        var copied: [String] = []
        preview.onCopyText = { copied.append($0); return true }
        preview.textView.setSelectedRange(NSRange(location: 3, length: 2))
        controls.formatButton.performClick(nil)
        #expect(controls.isFormatting && !controls.formatButton.isEnabled)
        try await awaitFormatting(controls)
        #expect(preview.textView.string == (try JSONTextFormatter.format(original)))
        #expect(controls.isShowingFormatted && controls.originalButton.isEnabled)
        #expect(copied.isEmpty && NSPasteboard.general.changeCount == count)
        let range = (preview.textView.string as NSString).range(of: "900719925474099312345")
        preview.textView.setSelectedRange(range)
        preview.textView.copy(nil)
        #expect(copied == ["900719925474099312345"])
        controls.originalButton.performClick(nil)
        #expect(preview.textView.string == original)
        #expect(!controls.isShowingFormatted && !controls.originalButton.isEnabled)
        #expect(controls.formatButton.isEnabled)
        controls.formatButton.performClick(nil)
        #expect(controls.isShowingFormatted) // Cached result is immediate.
        #expect(NSPasteboard.general.changeCount == count)
    }

    @Test func malformedJSONKeepsTextSelectionAndReportsFailure() async throws {
        _ = NSApplication.shared
        let source = "{\"bad\": [1,]}"
        let preview = TextPreviewViewController(text: source)
        _ = preview.view
        let controls = try #require(preview.formatting)
        var status = ""
        controls.onStatus = { message, _ in status = message }
        preview.textView.setSelectedRange(NSRange(location: 1, length: 5))
        controls.formatJSON()
        try await awaitFormatting(controls)
        #expect(preview.textView.string == source)
        #expect(preview.textView.selectedRange() == NSRange(location: 1, length: 5))
        #expect(status.contains("格式化失败") && status.contains("第 1 行"))
        #expect(!controls.isShowingFormatted && controls.formatButton.isEnabled)
    }

    @Test func restoreDuringBackgroundFormattingRejectsStaleResult() async throws {
        _ = NSApplication.shared
        let original = "[" + Array(repeating: "12345678901234567890", count: 20_000).joined(separator: ",") + "]"
        let preview = TextPreviewViewController(text: original)
        _ = preview.view
        let controls = try #require(preview.formatting)
        controls.formatJSON()
        controls.showOriginal()
        #expect(preview.textView.string == original)
        // Queue a second request behind the cancelled one. Its completion proves
        // the old callback had a chance to arrive and was ignored.
        let next = JSONPreviewFormattingController(original: "{\"ok\":true}")
        next.formatJSON()
        try await awaitFormatting(next)
        #expect(!controls.isShowingFormatted && preview.textView.string == original)
        #expect(controls.formatButton.isEnabled)
    }

    @Test func formattingDoesNotChangeHistoryPayloadOrCloseWindow() async throws {
        _ = NSApplication.shared
        let entry = HistoryEntry(payload: .text(#"{"b":2,"a":1}"#))
        let controller = try #require(EntryPreviewWindowController(entry: entry, onCopyText: { _ in Issue.record("Unexpected copy"); return false }))
        defer { controller.hide() }
        let preview = try #require(controller.contentController as? TextPreviewViewController)
        let controls = try #require(preview.formatting)
        let before = NSPasteboard.general.changeCount
        controls.formatJSON()
        try await awaitFormatting(controls)
        #expect(entry.payload == .text(#"{"b":2,"a":1}"#))
        #expect(NSPasteboard.general.changeCount == before)
        #expect(preview.textView.isSelectable && !preview.textView.isEditable)
    }

    @Test func filesDoNotOfferJSONFormattingAndMinimumWidthFitsControls() throws {
        _ = NSApplication.shared
        let file = try #require(EntryPreviewWindowController(entry: HistoryEntry(payload: .files(["file:///tmp/demo.json"])), onCopyText: { _ in true }))
        #expect((file.contentController as? TextPreviewViewController)?.formatting == nil)
        let window = try #require(EntryPreviewWindowController(entry: HistoryEntry(payload: .text("{}")), onCopyText: { _ in true }))
        defer { file.hide(); window.hide() }
        window.window?.setContentSize(NSSize(width: 470, height: 300))
        let root = try #require(window.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let preview = try #require(window.contentController as? TextPreviewViewController)
        let controls = try #require(preview.formatting)
        #expect(!root.hasAmbiguousLayout)
        #expect(preview.scrollView.frame.width == preview.view.bounds.width)
        #expect(controls.formatButton.frame.width > 70)
        #expect(controls.originalButton.frame.width > 60)
    }
}
