import Foundation
import SQLite3

public struct LocalStorageError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

enum SQLValue {
    case text(String), blob(Data), number(Int64), null
    var text: String { if case .text(let value) = self { return value }; return "" }
    var number: Int64 { if case .number(let value) = self { return value }; return 0 }
}

/// Owned by one repository; the repository serializes every call.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    init(url: URL) throws {
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else { close(); throw LocalStorageError("无法打开收藏库，请检查存储位置和磁盘空间。") }
        sqlite3_busy_timeout(handle, 3000)
    }
    func close() { if let handle { sqlite3_close_v2(handle) }; handle = nil }
    deinit { close() }

    @discardableResult
    func run(_ sql: String, _ bindings: [SQLValue] = []) throws -> [[SQLValue]] {
        guard let handle else { throw LocalStorageError("收藏库正在切换存储位置，请稍后重试。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LocalStorageError("收藏库读取失败，原数据已保留。")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bindings.enumerated() {
            let slot = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let text): result = text.withCString { sqlite3_bind_text(statement, slot, $0, Int32(text.utf8.count), transient) }
            case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob(statement, slot, $0.baseAddress, Int32(data.count), transient) }
            case .number(let value): result = sqlite3_bind_int64(statement, slot, value)
            case .null: result = sqlite3_bind_null(statement, slot)
            }
            guard result == SQLITE_OK else { throw LocalStorageError("收藏内容无法写入。") }
        }
        var rows: [[SQLValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw LocalStorageError("收藏操作未完成（\(result)），请检查目录权限与磁盘空间。") }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: return .number(sqlite3_column_int64(statement, column))
                case SQLITE_BLOB:
                    guard let bytes = sqlite3_column_blob(statement, column) else { return .blob(Data()) }
                    return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))))
                case SQLITE_TEXT:
                    guard let bytes = sqlite3_column_text(statement, column) else { return .text("") }
                    let count = Int(sqlite3_column_bytes(statement, column))
                    return .text(String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self))
                default: return .null
                }
            })
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do { let value = try body(); try run("COMMIT"); return value }
        catch { try? run("ROLLBACK"); throw error }
    }
}
