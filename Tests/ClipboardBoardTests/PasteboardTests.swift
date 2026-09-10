import AppKit
import Testing
import Foundation
import ClipboardCore
@testable import ClipboardBoard

@Suite(.serialized)
@MainActor
final class PasteboardTests {
    private var board: NSPasteboard!
    init() { board = NSPasteboard.withUniqueName() }
    deinit { board.releaseGlobally(); board = nil }

    @Test func testPlainTextRoundTripDoesNotChangeUnicodeOrWhitespace() {
        let monitor = PasteboardMonitor(pasteboard: board)
        let text = "  测试 👋\n\tsecond line\r\n"
        #expect(monitor.write(.text(text)))
        #expect(PasteboardMonitor.read(from: board) == .text(text))
    }

    @Test func testPNGAndTIFFRepresentationsAvailableOnImagePaste() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let blue = NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(blue, atX: x, y: y) } }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let monitor = PasteboardMonitor(pasteboard: board)
        #expect(monitor.write(.image(png)))
        #expect(PasteboardMonitor.read(from: board) == .image(png))
        #expect(board.data(forType: .tiff) != nil)
        board.clearContents()
        board.setData(bitmap.tiffRepresentation, forType: .tiff)
        guard case .image(let converted) = PasteboardMonitor.read(from: board) else {
            Issue.record("TIFF must be captured as an image")
            return
        }
        let read = try #require(NSBitmapImageRep(data: converted))
        #expect(read.pixelsWide == 2)
        #expect(read.pixelsHigh == 2)
        let color = try #require(read.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(abs(color.blueComponent - 0.9) < 0.02)
    }

    @Test func testSensitiveAndTransientCopiesAreIgnored() {
        for type in PasteboardMonitor.ignoredTypes {
            board.clearContents()
            board.setString("private", forType: .string)
            board.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            #expect(PasteboardMonitor.read(from: board) == nil)
        }
    }

    @Test func testEmptyAndUnsupportedClipboardAreIgnored() {
        #expect(PasteboardMonitor.read(from: board) == nil)
        board.setString("", forType: .string)
        #expect(PasteboardMonitor.read(from: board) == nil)
        board.clearContents()
        board.setData(Data([1, 2]), forType: NSPasteboard.PasteboardType("test.unsupported"))
        #expect(PasteboardMonitor.read(from: board) == nil)
    }

    @Test func testMonitorCapturesOnlyChangesAndSuppressesItsOwnWrites() {
        board.setString("before launch", forType: .string)
        let monitor = PasteboardMonitor(pasteboard: board)
        var captured: [ClipPayload] = []
        monitor.onCapture = { payload, _ in captured.append(payload) }
        monitor.poll()
        #expect(captured.isEmpty)
        board.clearContents()
        board.setString("new copy", forType: .string)
        monitor.poll()
        monitor.poll()
        #expect(captured == [.text("new copy")])
        #expect(monitor.write(.text("selected history")))
        monitor.poll()
        #expect(captured.count == 1)
    }

    @Test func testPausedCopiesAreNotCapturedAfterResume() {
        let monitor = PasteboardMonitor(pasteboard: board)
        var captured: [ClipPayload] = []
        monitor.onCapture = { payload, _ in captured.append(payload) }
        monitor.isPaused = true
        board.clearContents()
        board.setString("paused copy", forType: .string)
        monitor.poll()
        monitor.isPaused = false
        monitor.poll()
        #expect(captured.isEmpty)
        board.clearContents()
        board.setString("resumed copy", forType: .string)
        monitor.poll()
        #expect(captured == [.text("resumed copy")])
    }

    @Test func testCorruptImageDoesNotClearCurrentClipboard() {
        let monitor = PasteboardMonitor(pasteboard: board)
        board.setString("keep", forType: .string)
        #expect(!(monitor.write(.image(Data([0, 1, 2])))))
        #expect(board.string(forType: .string) == "keep")
    }

    @Test func testDeletedFileDoesNotClearCurrentClipboard() {
        let monitor = PasteboardMonitor(pasteboard: board)
        board.setString("keep", forType: .string)
        #expect(!(monitor.write(.files(["file:///nonexistent/\(UUID().uuidString)"]))))
        #expect(board.string(forType: .string) == "keep")
    }
}
