import Foundation
import CryptoKit

/// Unlimited by item count. Only metadata is paged into the library list;
/// full text/images are decoded on demand for one preview or copy operation.
public final class FavoritesRepository {
    public let fileURL: URL
    private let database: SQLiteDatabase
    private let lock = NSRecursiveLock()
    public init(directoryURL: URL) throws {
        try PrivateDataFile.prepareDirectory(directoryURL)
        fileURL = directoryURL.appendingPathComponent("favorites.sqlite")
        database = try SQLiteDatabase(url: fileURL)
        do {
            let version = try database.run("PRAGMA user_version").first?.first?.number ?? 0
            guard version == 0 || version == 1 else { throw DataFormatError.newerVersion(Int(version)) }
            try database.run("PRAGMA foreign_keys=ON")
            try database.run("PRAGMA journal_mode=DELETE")
            try database.run("PRAGMA synchronous=EXTRA")
            try database.run("PRAGMA fullfsync=ON")
            try database.run("PRAGMA secure_delete=ON")
            if version == 0 {
                try database.transaction {
                    try database.run("CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE)")
                    try database.run("CREATE TABLE favorites (id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL UNIQUE, title TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL, folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL, added INTEGER NOT NULL, thumbnail BLOB, search_text TEXT NOT NULL, payload BLOB NOT NULL)")
                    try database.run("CREATE INDEX favorites_folder ON favorites(folder_id, added DESC)")
                    try database.run("CREATE INDEX favorites_added ON favorites(added DESC,id)")
                    try database.run("PRAGMA user_version=1")
                }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { database.close(); throw error }
    }
    private func serialized<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    public func close() { serialized { database.close() } }
    public func validate() throws {
        try serialized {
            guard try database.run("PRAGMA quick_check").first?.first?.text == "ok" else { throw LocalStorageError(L10n.tr("收藏库校验失败，原文件已保留。")) }
        }
    }
    private func fingerprint(_ payload: ClipPayload) throws -> (String, Data) {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        return (SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), data)
    }
    public func favoriteID(for payload: ClipPayload) throws -> UUID? {
        let key = try fingerprint(payload).0
        return try serialized { try database.run("SELECT id FROM favorites WHERE fingerprint=?", [.text(key)]).first.flatMap { UUID(uuidString: $0[0].text) } }
    }
    @discardableResult
    public func add(_ entry: HistoryEntry, folderID: UUID? = nil, thumbnail: Data? = nil) throws -> UUID {
        guard entry.payload.isValid, entry.payload.byteCount <= 8 * 1024 * 1024 else { throw LocalStorageError(L10n.tr("这条内容为空或超过单条 8 MiB 限制。")) }
        let (key, data) = try fingerprint(entry.payload)
        return try serialized {
            if let row = try database.run("SELECT id FROM favorites WHERE fingerprint=?", [.text(key)]).first, let id = UUID(uuidString: row[0].text) { return id }
            let id = UUID()
            let kind: String, title: String
            switch entry.payload {
            case .text(let text): kind = "文本"; title = String(text.prefix(120)).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            case .image: kind = "图片"; title = "图片收藏"
            case .files(let paths): kind = "文件"; title = String(paths.compactMap { URL(string: $0)?.lastPathComponent }.joined(separator: "、").prefix(120))
            }
            try database.run("INSERT INTO favorites (id,fingerprint,payload,title,kind,source,search_text,folder_id,added,thumbnail) VALUES (?,?,?,?,?,?,?,?,?,?)", [.text(id.uuidString),.text(key),.blob(data),.text(title),.text(kind),.text(entry.sourceName),.text(entry.payload.searchableText),folderID.map { .text($0.uuidString) } ?? .null,.number(Int64(Date().timeIntervalSince1970 * 1000)),thumbnail.flatMap { $0.count <= 256 * 1024 ? .blob($0) : nil } ?? .null])
            return id
        }
    }
    public func entry(id: UUID) throws -> HistoryEntry? {
        try serialized {
            guard let row = try database.run("SELECT payload,source FROM favorites WHERE id=?", [.text(id.uuidString)]).first,
                  case .blob(let data) = row[0] else { return nil }
            return HistoryEntry(id: id, payload: try JSONDecoder().decode(ClipPayload.self, from: data), sourceName: row[1].text)
        }
    }
    private func filter(_ scope: FavoriteScope, _ query: String) -> (String, [SQLValue]) {
        var clauses = ["1=1"], values: [SQLValue] = []
        switch scope {
        case .all: break
        case .unfiled: clauses.append("folder_id IS NULL")
        case .folder(let id): clauses.append("folder_id=?"); values.append(.text(id.uuidString))
        }
        if !query.isEmpty {
            clauses.append("(instr(lower(search_text),lower(?))>0 OR instr(lower(source),lower(?))>0 OR instr(lower(title),lower(?))>0)")
            values += [.text(query),.text(query),.text(query)]
        }
        return (clauses.joined(separator: " AND "), values)
    }
    public func page(scope: FavoriteScope = .all, query: String = "", offset: Int = 0, limit: Int = 100) throws -> FavoritePage {
        try serialized {
            let (condition, values) = filter(scope, query)
            let total = Int(try database.run("SELECT count(*) FROM favorites WHERE \(condition)", values)[0][0].number)
            let rows = try database.run("SELECT id,title,kind,source,folder_id,thumbnail FROM favorites WHERE \(condition) ORDER BY added DESC,id LIMIT ? OFFSET ?", values + [.number(Int64(min(max(limit,1),200))),.number(Int64(max(offset,0)))])
            return FavoritePage(items: rows.compactMap { row in
                guard let id = UUID(uuidString: row[0].text) else { return nil }
                return FavoriteSummary(id: id, title: row[1].text, kind: row[2].text, source: row[3].text, folderID: UUID(uuidString: row[4].text), thumbnail: { if case .blob(let data) = row[5] { return data }; return nil }())
            }, total: total)
        }
    }
    public func folders() throws -> [FavoriteFolder] {
        try serialized { try database.run("SELECT f.id,f.name,count(v.id) FROM folders f LEFT JOIN favorites v ON v.folder_id=f.id GROUP BY f.id ORDER BY f.name COLLATE NOCASE").compactMap { row in
            UUID(uuidString: row[0].text).map { FavoriteFolder(id: $0,name: row[1].text,count: Int(row[2].number)) }
        } }
    }
    private func checkedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw LocalStorageError(L10n.tr("文件夹名称需为 1–60 个字符，不能含换行或控制字符。")) }
        let reserved = AppLanguage.allCases.flatMap { language in
            ["全部收藏", "未分类"].map { L10n.text($0, language: language) }
        }
        guard !reserved.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw LocalStorageError(L10n.tr("请使用不同于“全部收藏”和“未分类”的文件夹名称。"))
        }
        return name
    }
    @discardableResult public func createFolder(name: String) throws -> UUID {
        let name = try checkedName(name), id = UUID()
        try serialized {
            guard try database.run("SELECT id FROM folders WHERE name=?",[.text(name)]).isEmpty else { throw LocalStorageError(L10n.tr("同名文件夹已存在。")) }
            try database.run("INSERT INTO folders VALUES (?,?)", [.text(id.uuidString),.text(name)])
        }
        return id
    }
    public func renameFolder(id: UUID, name: String) throws {
        let name = try checkedName(name)
        try serialized {
            guard try database.run("SELECT id FROM folders WHERE name=? AND id<>?",[.text(name),.text(id.uuidString)]).isEmpty else { throw LocalStorageError(L10n.tr("同名文件夹已存在。")) }
            try database.run("UPDATE folders SET name=? WHERE id=?", [.text(name),.text(id.uuidString)])
        }
    }
    public func deleteFolder(id: UUID) throws {
        _ = try serialized { try database.run("DELETE FROM folders WHERE id=?", [.text(id.uuidString)]) }
    }
    public func move(ids: Set<UUID>, to folderID: UUID?) throws {
        try serialized { try database.transaction {
            for id in ids { try database.run("UPDATE favorites SET folder_id=? WHERE id=?", [folderID.map { .text($0.uuidString) } ?? .null,.text(id.uuidString)]) }
        } }
    }
    public func remove(ids: Set<UUID>) throws {
        try serialized { try database.transaction {
            for id in ids { try database.run("DELETE FROM favorites WHERE id=?", [.text(id.uuidString)]) }
        } }
    }
    public func clear(scope: FavoriteScope = .all) throws {
        try serialized {
            let (condition, values) = filter(scope, "")
            try database.run("DELETE FROM favorites WHERE \(condition)",values)
            if scope == .all { _ = try? database.run("VACUUM") }
        }
    }
}
