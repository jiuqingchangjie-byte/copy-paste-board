import Foundation
import Testing
@testable import ClipboardCore

struct RecoveryTests {
    private func fixture() -> (URL, AppDataStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, AppDataStore(applicationURL: root.appendingPathComponent("ClipboardBoard.app")),
                root.appendingPathComponent("Legacy/history.json"))
    }

    @Test(arguments: [-10, 0, 1, 49, 50, 51, 1000, Int.max])
    func everyEntryPointCapsHistoryAtFifty(_ requested: Int) throws {
        let limit = min(max(requested, 1), 50)
        #expect(History(maxCount: requested).maxCount == limit)
        #expect(AppSettings(maxHistoryCount: requested).maxHistoryCount == limit)
        let json = Data("{\"maxHistoryCount\":\(requested)}".utf8)
        #expect(try JSONDecoder().decode(AppSettings.self, from: json).maxHistoryCount == limit)
    }

    @Test func oldThousandEntryHistoryKeepsTheNewestFiftyInOrder() throws {
        let (root, store, _) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = (1...1000).reversed().map { HistoryEntry(payload: .text("copy-\($0)")) }
        try PrivateDataFile.write(JSONEncoder().encode(old), to: store.history.fileURL)
        let history = History(entries: try store.history.load(), maxCount: 1000)
        #expect(history.entries == Array(old.prefix(50)))
        try store.history.save(history.entries)
        #expect(try store.history.load() == history.entries)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.history.fileURL)) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
    }

    @Test func fiftyEntryQueueDeduplicatesAndEvictsExactlyOne() {
        var history = History(maxCount: 50)
        for index in 1...50 { history.insert(HistoryEntry(payload: .text("\(index)"))) }
        history.insert(HistoryEntry(payload: .text("1")))
        #expect(history.entries.count == 50)
        #expect(history.entries.last?.payload == .text("2"))
        history.insert(HistoryEntry(payload: .files(["file:///tmp/queue-test.txt"])))
        #expect(history.entries.count == 50)
        #expect(!history.entries.contains { $0.payload == .text("2") })
        #expect(history.entries.last?.payload == .text("3"))
        let inserted = history.insert(HistoryEntry(payload: .image(Data())))
        #expect(!inserted)
        #expect(history.entries.count == 50)
    }

    @Test func repairCorruptSettingsPreservesHealthyHistoryAndExactOriginal() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = [HistoryEntry(payload: .text("preserve healthy history"))]
        try store.history.save(entries)
        let broken = Data("broken-settings".utf8)
        try PrivateDataFile.write(broken, to: store.settingsURL)
        let copies = try store.repairCorruptFiles(legacyHistoryURL: legacy, fallbackSettings: AppSettings(maxHistoryCount: 50))
        #expect(copies.count == 1)
        #expect(try Data(contentsOf: copies[0]) == broken)
        #expect(try store.history.load() == entries)
        #expect(try store.loadSettings().maxHistoryCount == 50)
        #expect(try FileManager.default.attributesOfItem(atPath: copies[0].path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func brokenHistoryIsArchivedAndNeverSilentlyRestoredAfterClear() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.saveSettings(AppSettings(maxHistoryCount: 20))
        let broken = Data("incomplete history".utf8)
        try PrivateDataFile.write(broken, to: store.history.fileURL)
        let copies = try store.repairCorruptFiles(legacyHistoryURL: legacy, fallbackSettings: AppSettings())
        #expect(try Data(contentsOf: copies[0]) == broken)
        #expect(try store.loadSettings().maxHistoryCount == 20)
        #expect(try store.history.load().isEmpty)
        try store.history.save([HistoryEntry(payload: .text("new"))])
        try store.history.save([])
        #expect(try store.history.load().isEmpty)
        #expect(try store.repairCorruptFiles(legacyHistoryURL: legacy, fallbackSettings: AppSettings()).isEmpty)
    }

    @Test func unsupportedFutureFormatIsNeverRebuilt() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.saveSettings(AppSettings())
        let future = Data(#"{"schemaVersion":99,"entries":[]}"#.utf8)
        try PrivateDataFile.write(future, to: store.history.fileURL)
        #expect(throws: DataFormatError.newerVersion(99)) { try store.history.load() }
        #expect(throws: DataFormatError.newerVersion(99)) {
            try store.repairCorruptFiles(legacyHistoryURL: legacy, fallbackSettings: AppSettings())
        }
        #expect(try Data(contentsOf: store.history.fileURL) == future)
        #expect(!FileManager.default.fileExists(atPath: store.directoryURL.appendingPathComponent("Recovery").path))
        #expect(throws: DataFormatError.newerVersion(99)) {
            try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion":99}"#.utf8))
        }
    }

    @Test func failedArchiveDoesNotReplaceTheDamagedOriginal() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = Data("keep exact original".utf8)
        try PrivateDataFile.write(broken, to: store.history.fileURL)
        try Data("directory blocked".utf8).write(to: store.directoryURL.appendingPathComponent("Recovery"))
        #expect(throws: (any Error).self) {
            try store.repairCorruptFiles(legacyHistoryURL: legacy, fallbackSettings: AppSettings())
        }
        #expect(try Data(contentsOf: store.history.fileURL) == broken)
    }

    @Test func corruptLegacyHistoryCanRecoverWithoutDestroyingLegacyFile() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = Data("legacy broken".utf8)
        try PrivateDataFile.write(broken, to: legacy)
        let copies = try store.repairCorruptFiles(legacyHistoryURL: legacy, fallbackSettings: AppSettings())
        #expect(copies.count == 1)
        #expect(try Data(contentsOf: legacy) == broken)
        #expect(try store.history.load().isEmpty)
    }

    @Test func retryPreservesSessionCopiesDeletionsAndClear() {
        let a = HistoryEntry(payload: .text("A"))
        let b = HistoryEntry(payload: .text("B"))
        let c = HistoryEntry(payload: .text("C"))
        let merged = History.recovering([a, b], keeping: [c], removedIDs: [a.id], wasCleared: false, maxCount: 50)
        #expect(merged.entries == [c, b])
        let cleared = History.recovering([a, b], keeping: [c], removedIDs: [], wasCleared: true, maxCount: 50)
        #expect(cleared.entries == [c])
        let duplicate = HistoryEntry(payload: .text("B"))
        let deduped = History.recovering([a, b], keeping: [duplicate], removedIDs: [], wasCleared: false, maxCount: 50)
        #expect(deduped.entries == [duplicate, a])
    }
}
