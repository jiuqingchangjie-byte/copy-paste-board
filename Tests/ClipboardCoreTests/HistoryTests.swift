import Testing
import Foundation
@testable import ClipboardCore

struct HistoryTests {
    private func entry(_ text: String) -> HistoryEntry { HistoryEntry(payload: .text(text)) }

    @Test func testDefaultRetainsTenNewestCopies() {
        var history = History()
        for number in 1...15 { history.insert(entry("\(number)")) }
        #expect(history.entries.count == 10)
        #expect(history.entries.first?.payload == .text("15"))
        #expect(history.entries.last?.payload == .text("6"))
    }

    @Test(arguments: [1, 3, 10, 37])
    func everyNewCopyEvictsOnlyTheOldestAtTheConfiguredLimit(_ limit: Int) {
        var history = History(maxCount: limit)
        for number in 1...(limit + 8) {
            history.insert(entry("copy-\(number)"))
            let expected = (max(1, number - limit + 1)...number).reversed().map { ClipPayload.text("copy-\($0)") }
            #expect(history.entries.map(\.payload) == expected)
            #expect(history.entries.count == min(number, limit))
        }
    }

    @Test func largeImagesDoNotTriggerAnEarlierAggregateCapacityEviction() {
        var history = History(maxCount: 5)
        for number in 1...7 {
            history.insert(HistoryEntry(payload: .image(Data(repeating: UInt8(number), count: 8 * 1024 * 1024))))
        }
        #expect(history.entries.count == 5)
        let numbers = history.entries.compactMap { entry -> UInt8? in
            if case .image(let data) = entry.payload { return data.first }
            return nil
        }
        #expect(numbers == [7, 6, 5, 4, 3])
    }

    @Test func testDuplicateMovesToFrontWithoutAccumulatingCopies() {
        var history = History()
        history.insert(entry("A"))
        history.insert(entry("B"))
        let inserted19 = history.insert(entry("A"))
        #expect(inserted19)
        #expect(history.entries.map(\.payload) == [.text("A"), .text("B")])
        let inserted21 = !(history.insert(entry("A")))
        #expect(inserted21)
        #expect(history.entries.count == 2)
    }

    @Test func testWhitespaceUnicodeAndLineBreaksArePreserved() {
        let text = "  中文 👨‍👩‍👧‍👦\n\t第二行\r\n "
        var history = History()
        history.insert(entry(text))
        #expect(history.entries[0].payload == .text(text))
        let inserted30 = history.insert(entry(" \n"))
        #expect(inserted30)
        let inserted31 = !(history.insert(entry("")))
        #expect(inserted31)
    }

    @Test func testConfigurableLimitAndImmediateReductionKeepNewest() {
        var history = History(maxCount: 20)
        for number in 1...20 { history.insert(entry("\(number)")) }
        history = History(entries: history.entries, maxCount: 3)
        #expect(history.entries.map(\.payload) == [.text("20"), .text("19"), .text("18")])
        history = History(entries: history.entries, maxCount: 30)
        #expect(history.entries.count == 3)
    }

    @Test func testOneEntryLimit() {
        var history = History(maxCount: 1)
        history.insert(entry("one"))
        history.insert(entry("two"))
        #expect(history.entries.map(\.payload) == [.text("two")])
    }

    @Test func testByteBudgetTrimsOldestAndRejectsOversizedEntryWithoutEviction() {
        var history = History(maxBytes: 6, maxItemBytes: 4)
        history.insert(entry("aa"))
        history.insert(entry("bbb"))
        history.insert(entry("cccc"))
        #expect(history.entries.map(\.payload) == [.text("cccc")])
        let inserted56 = !(history.insert(entry("12345")))
        #expect(inserted56)
        #expect(history.entries.map(\.payload) == [.text("cccc")])
    }

    @Test func testUTF8BudgetCountsBytesInsteadOfCharacters() {
        var history = History(maxBytes: 4, maxItemBytes: 4)
        let inserted62 = history.insert(entry("中"))
        #expect(inserted62)
        let inserted63 = !(history.insert(entry("中文")))
        #expect(inserted63)
    }

    @Test func testDifferentTypesRemainDistinctAndImagesDeduplicate() {
        var history = History()
        let image = HistoryEntry(payload: .image(Data([1, 2, 3])))
        history.insert(image)
        history.insert(entry("image"))
        history.insert(image)
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.payload == image.payload)
    }

    @Test func testRemoveAndClear() {
        var history = History()
        let first = entry("first")
        history.insert(first)
        history.insert(entry("second"))
        history.remove(id: first.id)
        #expect(history.entries.count == 1)
        history.clear()
        #expect(history.entries.isEmpty)
    }

    @Test func testSearchByContentSourceAndImageKeyword() {
        var history = History()
        history.insert(HistoryEntry(payload: .text("Hello 中文"), sourceName: "TextEdit"))
        history.insert(HistoryEntry(payload: .image(Data([1]))))
        #expect(history.matching(" hello ").count == 1)
        #expect(history.matching("中文").count == 1)
        #expect(history.matching("textedit").count == 1)
        #expect(history.matching("图片").count == 1)
        #expect(history.matching(" \n").count == 2)
        #expect(history.matching("missing").isEmpty)
    }

    @Test func testInvalidPayloadsRejected() {
        var history = History()
        let inserted101 = !(history.insert(HistoryEntry(payload: .image(Data()))))
        #expect(inserted101)
        let inserted102 = !(history.insert(HistoryEntry(payload: .files([]))))
        #expect(inserted102)
        let inserted103 = !(history.insert(HistoryEntry(payload: .files(["https://example.com"]))))
        #expect(inserted103)
    }

    @Test func testDiskRoundTripAndClearSurviveRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = HistoryStorage(fileURL: directory.appendingPathComponent("history.json"))
        #expect(try storage.load() == [])
        let entries = [entry("中文\n👋"), HistoryEntry(payload: .image(Data([0, 1, 255])))]
        try storage.save(entries)
        #expect(try storage.load() == entries)
        let permissions = try FileManager.default.attributesOfItem(atPath: storage.fileURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try storage.save([])
        #expect(try storage.load().isEmpty)
    }

    @Test func testCorruptStorageThrows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        try Data("broken JSON".utf8).write(to: file)
        #expect(throws: (any Error).self) { try HistoryStorage(fileURL: file).load() }
    }
}
