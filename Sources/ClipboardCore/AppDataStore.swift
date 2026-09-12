import Foundation

public struct AppSettings: Codable, Equatable {
    public let schemaVersion = 1
    public var maxHistoryCount: Int
    public var panelOrigin: [Double]?
    public var hasLaunched: Bool
    public var shortcut: KeyboardShortcut
    public var preview: PreviewSettings

    public init(maxHistoryCount: Int = 10, panelOrigin: [Double]? = nil, hasLaunched: Bool = false,
                preview: PreviewSettings = PreviewSettings(), shortcut: KeyboardShortcut = .default) {
        self.maxHistoryCount = min(max(maxHistoryCount, 1), History.maximumCount)
        self.panelOrigin = panelOrigin.flatMap { $0.count == 2 && $0.allSatisfy(\.isFinite) ? $0 : nil }
        self.hasLaunched = hasLaunched
        self.preview = preview
        self.shortcut = shortcut.isValid ? shortcut : .default
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, maxHistoryCount, panelOrigin, hasLaunched, preview, shortcut }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version == 1 else { throw DataFormatError.newerVersion(version) }
        self.init(maxHistoryCount: try values.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 10,
                  panelOrigin: try values.decodeIfPresent([Double].self, forKey: .panelOrigin),
                  hasLaunched: try values.decodeIfPresent(Bool.self, forKey: .hasLaunched) ?? false,
                  preview: try values.decodeIfPresent(PreviewSettings.self, forKey: .preview) ?? PreviewSettings(),
                  shortcut: try values.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut) ?? .default)
    }
}

/// User data lives beside the .app. Writes never modify the signed app bundle.
public struct AppDataStore {
    public let directoryURL: URL
    public var history: HistoryStorage { HistoryStorage(fileURL: directoryURL.appendingPathComponent("history.json")) }
    public var settingsURL: URL { directoryURL.appendingPathComponent("settings.json") }

    public init(applicationURL: URL) {
        let installDirectory = applicationURL.pathExtension == "app"
            ? applicationURL.deletingLastPathComponent() : applicationURL
        directoryURL = installDirectory.appendingPathComponent("ClipboardBoardData", isDirectory: true)
    }

    public init(directoryURL: URL) { self.directoryURL = directoryURL.standardizedFileURL }

    public func loadSettings() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: settingsURL))
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try PrivateDataFile.write(JSONEncoder().encode(settings), to: settingsURL)
    }

    /// Explicit user recovery only. Never treat permission errors or a future
    /// format as corrupt data. Preserve exact bytes before replacing anything.
    public func repairCorruptFiles(legacyHistoryURL: URL, fallbackSettings: AppSettings) throws -> [URL] {
        let historySource = FileManager.default.fileExists(atPath: history.fileURL.path)
            ? history.fileURL : legacyHistoryURL
        var broken: [URL] = []
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let data = try Data(contentsOf: settingsURL)
            do { _ = try JSONDecoder().decode(AppSettings.self, from: data) }
            catch is DecodingError { broken.append(settingsURL) }
        }
        if FileManager.default.fileExists(atPath: historySource.path) {
            do { _ = try HistoryStorage(fileURL: historySource).load() }
            catch is DecodingError { broken.append(historySource) }
        }
        guard !broken.isEmpty else { return [] }
        let archive = directoryURL.appendingPathComponent("Recovery/\(UUID().uuidString)", isDirectory: true)
        var copies: [URL] = []
        // All archives must succeed before replacing any live file.
        for source in broken {
            let destination = archive.appendingPathComponent(source.lastPathComponent)
            try PrivateDataFile.write(Data(contentsOf: source), to: destination)
            copies.append(destination)
        }
        if broken.contains(settingsURL) { try saveSettings(fallbackSettings) }
        if broken.contains(historySource) { try history.save([]) }
        return copies
    }

    public func migrateLegacyIfNeeded(historyURL: URL, settings: AppSettings) throws {
        if !FileManager.default.fileExists(atPath: settingsURL.path) { try saveSettings(settings) }
        guard !FileManager.default.fileExists(atPath: history.fileURL.path) else { return }
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            try history.save([])
            return
        }
        // Validate first, then move intact. A failed migration leaves the original
        // file available, and an existing (including empty) new history always wins.
        _ = try HistoryStorage(fileURL: historyURL).load()
        try PrivateDataFile.prepareDirectory(directoryURL)
        try FileManager.default.moveItem(at: historyURL, to: history.fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: history.fileURL.path)
    }
}
