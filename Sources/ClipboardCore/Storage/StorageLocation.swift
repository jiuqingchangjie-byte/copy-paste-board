import Foundation

/// Small bootstrap file stays beside the app, independently of the data folder.
/// Fixed-path app updates therefore continue to resolve the same custom folder.
public struct StorageLocation {
    public let pointerURL: URL
    public let defaultDirectory: URL
    public init(applicationURL: URL) {
        let store = AppDataStore(applicationURL: applicationURL)
        defaultDirectory = store.directoryURL
        pointerURL = defaultDirectory.deletingLastPathComponent().appendingPathComponent("ClipboardBoardConfig/storage-location.json")
    }
    public var isCustom: Bool { FileManager.default.fileExists(atPath: pointerURL.path) }
    public func selectedDirectory() throws -> URL {
        guard isCustom else { return defaultDirectory }
        let document = try JSONDecoder().decode(LocationDocument.self, from: Data(contentsOf: pointerURL))
        guard document.schemaVersion == 1 else { throw DataFormatError.newerVersion(document.schemaVersion) }
        let url = URL(fileURLWithPath: document.directoryPath, isDirectory: true).standardizedFileURL
        guard document.directoryPath.hasPrefix("/") else { throw LocalStorageError(L10n.tr("存储位置配置无效，原文件已保留。")) }
        return url
    }
    public func resolve() throws -> AppDataStore {
        let url = try selectedDirectory()
        guard !isCustom || ["history.json", "settings.json", "favorites.sqlite"].allSatisfy({
            FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
        }) else {
            throw LocalStorageError(L10n.tr("自定义存储位置不可用或数据缺失：{0}。请恢复目录连接后重试；不会自动切换到空目录。", String(describing: url.path)))
        }
        return AppDataStore(directoryURL: url)
    }
    public func save(directory: URL) throws {
        let document = LocationDocument(schemaVersion: 1, directoryPath: directory.standardizedFileURL.path)
        try PrivateDataFile.write(JSONEncoder().encode(document), to: pointerURL)
    }
    private struct LocationDocument: Codable { let schemaVersion: Int; let directoryPath: String }
}
