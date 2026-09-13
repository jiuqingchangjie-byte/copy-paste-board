import Foundation
import Testing
@testable import ClipboardCore

struct LocalizationTests {
    @Test func allLanguagesHaveCompleteCatalogAndMatchingPlaceholders() throws {
        let expression = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func tokens(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        #expect(L10n.catalog.count >= 290)
        for (key, translations) in L10n.catalog {
            #expect(translations.count == 3)
            for translation in translations {
                #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(tokens(key) == tokens(translation), "\(key)")
            }
            #expect(!translations[0].unicodeScalars.contains { (0x4e00...0x9fff).contains($0.value) }, "English: \(key)")
            #expect(!translations[2].unicodeScalars.contains { (0x4e00...0x9fff).contains($0.value) }, "Korean: \(key)")
        }
    }
    @Test func systemLanguageMatchingUsesOnlyFourLanguages() {
        for identifier in ["zh", "zh-CN", "zh-TW", "zh-HK", "zh-Hant", "zh_Hant_MO"] {
            #expect(AppLanguage.preferred(from: [identifier]) == .chinese)
        }
        #expect(AppLanguage.preferred(from: ["en-GB"]) == .english)
        #expect(AppLanguage.preferred(from: ["ja-JP"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["ko-KR"]) == .korean)
        #expect(AppLanguage.preferred(from: ["fr-FR", "ja"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["de-DE"]) == .english)
        #expect(AppLanguage.preferred(from: []) == .english)
        #expect(AppLanguage.allCases.map(\.nativeName) == ["中文", "English", "日本語", "한국어"])
    }
    @Test func oldSettingsKeepChineseAndOtherPreferences() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"maxHistoryCount":23,"hasLaunched":true,"panelOrigin":[100,200]}"#.utf8))
        #expect(settings.language == .chinese)
        #expect(settings.maxHistoryCount == 23 && settings.hasLaunched)
        #expect(settings.panelOrigin == [100,200])
    }
    @Test func unknownOrMalformedLanguageDoesNotDiscardOtherSettings() throws {
        for value in [#""unknown""#, "null", "123", "{}"] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"language\":\(value),\"maxHistoryCount\":31}".utf8))
            #expect(settings.language == .english)
            #expect(settings.maxHistoryCount == 31)
        }
    }
    @Test func savedLanguageSurvivesReloadAndStorageMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppDataStore(directoryURL: root.appendingPathComponent("data"))
        let entries = [HistoryEntry(payload: .text("原文 English 日本語 한국어 {1} 100%"))]
        try store.history.save(entries)
        for language in AppLanguage.allCases {
            let settings = AppSettings(maxHistoryCount: 17, hasLaunched: true, language: language)
            try store.saveSettings(settings)
            #expect(try store.loadSettings() == settings)
            #expect(try store.history.load() == entries)
        }
        let repository = try FavoritesRepository(directoryURL: store.directoryURL)
        try repository.add(entries[0]); repository.close()
        let location = StorageLocation(applicationURL: root.appendingPathComponent("ClipboardBoard.app"))
        let moved = try StorageRelocator.migrate(source: store, to: root.appendingPathComponent("moved"), location: location)
        #expect(try moved.loadSettings().language == .korean)
        #expect(try moved.history.load() == entries)
    }
    @Test func interpolationPreservesUntrustedTextVerbatim() {
        for language in AppLanguage.allCases {
            let name = "{1} %@ %s 日本語 한국어 👨‍👩‍👧‍👦"
            let result = L10n.text("删除“{0}”文件夹？", language: language, arguments: [name])
            #expect(result.contains(name))
            let message = L10n.text("第 {0} 行，第 {1} 列：{2}", language: language, arguments: ["2", "7", name])
            #expect(message.contains(name) && message.contains("2") && message.contains("7"))
        }
    }
    @Test func keyTermsDistinguishFavoritesFromWindowPinning() {
        #expect(L10n.text("取消收藏", language: .english) == "Remove from Favorites")
        #expect(L10n.text("置顶固定", language: .english) == "Keep on Top")
        #expect(L10n.text("粘贴", language: .japanese) == "ペースト")
        #expect(L10n.text("辅助功能权限…", language: .korean) == "손쉬운 사용 접근 권한…")
        #expect(L10n.text("JSON 格式化", language: .japanese) == "JSON を整形")
        #expect(L10n.text("JSON 格式化", language: .korean) == "JSON 서식 정리")
    }
    @Test func reservedFolderNamesCannotConflictAcrossLanguages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try FavoritesRepository(directoryURL: root); defer { repo.close() }
        for language in AppLanguage.allCases {
            for key in ["全部收藏", "未分类"] {
                #expect(throws: (any Error).self) { try repo.createFolder(name: L10n.text(key, language: language)) }
            }
        }
        let name = "My folder 我的文件夹 日本語 한국어"
        try repo.createFolder(name: name)
        #expect(try repo.folders().first?.name == name)
    }
}
