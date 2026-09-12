import Foundation
import Darwin

/// Replace only after a complete private file has been flushed. A crash before
/// rename leaves the previous snapshot; a crash after rename sees the new one.
enum PrivateDataFile {
    static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    static func write(_ data: Data, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory(directory)
        let temporary = directory.appendingPathComponent(".pending-\(UUID().uuidString)")
        let descriptor = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // macOS asks the storage device to flush its write cache when supported.
        _ = fcntl(descriptor, F_FULLFSYNC)
        guard Darwin.rename(temporary.path, fileURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let parent = Darwin.open(directory.path, O_RDONLY)
        if parent >= 0 { _ = fsync(parent); Darwin.close(parent) }
    }
}
