import Foundation
import CryptoKit
import Darwin

/// The caller drains history writes and closes the SQLite connection before
/// migration. The bootstrap pointer is the final commit; the source is retained.
public enum StorageRelocator {
    public static func migrate(source: AppDataStore, to destination: URL, location: StorageLocation) throws -> AppDataStore {
        let fm = FileManager.default
        let original = source.directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        guard !target.pathComponents.contains(where: { $0.lowercased().hasSuffix(".app") }) else {
            throw LocalStorageError("请选择应用包外的文件夹，避免破坏应用签名。")
        }
        if target == original { return source }
        guard !target.path.hasPrefix(original.path + "/"), !original.path.hasPrefix(target.path + "/") else {
            throw LocalStorageError("新目录不能位于当前数据目录内部，也不能是其上级目录。")
        }
        if fm.fileExists(atPath: target.path), !(try fm.contentsOfDirectory(atPath: target.path)).isEmpty {
            throw LocalStorageError("目标数据目录已有内容，请选择空目录；不会覆盖或合并已有历史。")
        }
        let parent = target.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".ClipboardBoardMigration-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        try assertNoSymlinks(original)
        try fm.copyItem(at: original, to: stage)
        let copied = AppDataStore(directoryURL: stage)
        _ = try copied.loadSettings()
        _ = try copied.history.load()
        if fm.fileExists(atPath: stage.appendingPathComponent("favorites.sqlite").path) {
            let repository = try FavoritesRepository(directoryURL: stage)
            try repository.validate()
            repository.close()
        }
        // Validate every copied byte after database validation/close.
        let originalFiles = try regularFiles(original)
        for relative in originalFiles {
            guard try digest(original.appendingPathComponent(relative)) == digest(stage.appendingPathComponent(relative)) else {
                throw LocalStorageError("迁移校验失败，仍使用原目录。")
            }
            let file = try FileHandle(forWritingTo: stage.appendingPathComponent(relative))
            try file.synchronize()
            _ = fcntl(file.fileDescriptor, F_FULLFSYNC)
            try file.close()
        }
        if fm.fileExists(atPath: target.path), Darwin.rmdir(target.path) != 0 {
            throw LocalStorageError("目标目录已被占用，迁移停止，原目录保持不变。")
        }
        try fm.moveItem(at: stage, to: target)
        let parentFD = Darwin.open(parent.path, O_RDONLY)
        if parentFD >= 0 { _ = fsync(parentFD); Darwin.close(parentFD) }
        try location.save(directory: target)
        return AppDataStore(directoryURL: target)
    }
    private static func assertNoSymlinks(_ root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                throw LocalStorageError("数据目录包含符号链接，迁移已停止，请先检查目录。")
            }
        }
    }
    private static func regularFiles(_ root: URL) throws -> [String] {
        var result: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        while let relative = enumerator?.nextObject() as? String {
            let url = root.appendingPathComponent(relative)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result.append(relative)
            }
        }
        return result
    }
    private static func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize()
    }
}
