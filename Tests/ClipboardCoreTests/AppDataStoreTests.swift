import Foundation
import Testing
@testable import ClipboardCore

struct AppDataStoreTests {
    private func fixture() -> (URL, AppDataStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardBoard-\(UUID().uuidString)")
        let store = AppDataStore(applicationURL: root.appendingPathComponent("Install/ClipboardBoard.app"))
        return (root, store, root.appendingPathComponent("Legacy/history.json"))
    }

    @Test func dataIsBesideTheApplicationAndSettingsSurviveRestart() throws {
        let (root, store, _) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.directoryURL == root.appendingPathComponent("Install/ClipboardBoardData", isDirectory: true))
        let settings = AppSettings(maxHistoryCount: 17, panelOrigin: [234, 567], hasLaunched: true)
        try store.saveSettings(settings)
        let reloaded = AppDataStore(applicationURL: root.appendingPathComponent("Install/ClipboardBoard.app"))
        #expect(try reloaded.loadSettings() == settings)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.settingsURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Install/ClipboardBoard.app/Contents/ClipboardBoardData").path))
    }

    @Test func migrationMovesExistingHistoryAndImportsSettings() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = [HistoryEntry(payload: .text("已有记录 👋")), HistoryEntry(payload: .image(Data([1, 2, 3])))]
        try HistoryStorage(fileURL: legacy).save(entries)
        let settings = AppSettings(maxHistoryCount: 3, panelOrigin: [10, 20], hasLaunched: true)
        try store.migrateLegacyIfNeeded(historyURL: legacy, settings: settings)
        #expect(try store.history.load() == entries)
        #expect(try store.loadSettings() == settings)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        try store.history.save([])
        try store.migrateLegacyIfNeeded(historyURL: legacy, settings: AppSettings())
        #expect(try store.history.load().isEmpty)
        #expect(try store.loadSettings() == settings)
    }

    @Test func existingNewHistoryIncludingAnEmptyOneIsNeverOverwrittenByLegacyData() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.history.save([])
        let settings = AppSettings(maxHistoryCount: 22)
        try store.saveSettings(settings)
        let old = [HistoryEntry(payload: .text("old"))]
        try HistoryStorage(fileURL: legacy).save(old)
        try store.migrateLegacyIfNeeded(historyURL: legacy, settings: AppSettings(maxHistoryCount: 5))
        #expect(try store.history.load().isEmpty)
        #expect(try store.loadSettings() == settings)
        #expect(try HistoryStorage(fileURL: legacy).load() == old)
    }

    @Test func unwritableDestinationDoesNotLoseLegacyHistory() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = [HistoryEntry(payload: .text("preserve me"))]
        try HistoryStorage(fileURL: legacy).save(old)
        try FileManager.default.createDirectory(at: store.directoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a file blocks the directory".utf8).write(to: store.directoryURL)
        #expect(throws: (any Error).self) {
            try store.migrateLegacyIfNeeded(historyURL: legacy, settings: AppSettings())
        }
        #expect(try HistoryStorage(fileURL: legacy).load() == old)
    }

    @Test func corruptLegacyDataIsPreservedForRecovery() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("not valid JSON".utf8)
        try data.write(to: legacy)
        #expect(throws: (any Error).self) {
            try store.migrateLegacyIfNeeded(historyURL: legacy, settings: AppSettings())
        }
        #expect(try Data(contentsOf: legacy) == data)
        #expect(!FileManager.default.fileExists(atPath: store.history.fileURL.path))
    }

    @Test func firstRunCreatesBothFilesAndClearSurvivesRestart() throws {
        let (root, store, legacy) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.migrateLegacyIfNeeded(historyURL: legacy, settings: AppSettings())
        #expect(try store.loadSettings().maxHistoryCount == 10)
        try store.history.save([HistoryEntry(payload: .text("new"))])
        try store.history.save([])
        #expect(try store.history.load().isEmpty)
    }

    @Test func settingsDefaultsAndValidation() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(AppSettings.self, from: Data("{}".utf8)) == AppSettings())
        let invalid = Data(#"{"maxHistoryCount":2000,"panelOrigin":[42],"hasLaunched":true}"#.utf8)
        let settings = try decoder.decode(AppSettings.self, from: invalid)
        #expect(settings.maxHistoryCount == 50)
        #expect(settings.panelOrigin == nil)
        #expect(settings.hasLaunched)
    }

    @Test func imageHistoryAboveTheOldFileSizeCapStillReloads() throws {
        let (root, store, _) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = (1...5).map {
            HistoryEntry(payload: .image(Data(repeating: UInt8($0), count: 8 * 1024 * 1024)))
        }
        try store.history.save(entries)
        let size = try store.history.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 48 * 1024 * 1024)
        #expect(try store.history.load() == entries)
    }
}
