import Foundation

public struct AppSettings: Codable, Equatable {
    public var maxHistoryCount: Int
    public var panelOrigin: [Double]?
    public var hasLaunched: Bool

    public init(maxHistoryCount: Int = 10, panelOrigin: [Double]? = nil, hasLaunched: Bool = false) {
        self.maxHistoryCount = min(max(maxHistoryCount, 1), 1000)
        self.panelOrigin = panelOrigin.flatMap { $0.count == 2 && $0.allSatisfy(\.isFinite) ? $0 : nil }
        self.hasLaunched = hasLaunched
    }

    private enum CodingKeys: String, CodingKey { case maxHistoryCount, panelOrigin, hasLaunched }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(maxHistoryCount: try values.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 10,
                  panelOrigin: try values.decodeIfPresent([Double].self, forKey: .panelOrigin),
                  hasLaunched: try values.decodeIfPresent(Bool.self, forKey: .hasLaunched) ?? false)
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

    public func loadSettings() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: settingsURL))
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try PrivateDataFile.write(JSONEncoder().encode(settings), to: settingsURL)
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
