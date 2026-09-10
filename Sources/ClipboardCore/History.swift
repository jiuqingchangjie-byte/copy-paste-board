import Foundation

public enum ClipPayload: Codable, Equatable {
    case text(String)
    case image(Data) // PNG
    case files([String]) // File URLs, without copying the files themselves.

    public var byteCount: Int {
        switch self {
        case .text(let text): return text.utf8.count
        case .image(let data): return data.count
        case .files(let urls): return urls.reduce(0) { $0 + $1.utf8.count }
        }
    }

    public var isValid: Bool {
        switch self {
        case .text(let text): return !text.isEmpty
        case .image(let data): return !data.isEmpty
        case .files(let urls): return !urls.isEmpty && urls.allSatisfy { URL(string: $0)?.isFileURL == true }
        }
    }

    public var searchableText: String {
        switch self {
        case .text(let text): return text
        case .image: return "图片 image png"
        case .files(let urls): return urls.compactMap { URL(string: $0)?.path }.joined(separator: "\n")
        }
    }
}

public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let payload: ClipPayload
    public let copiedAt: Date
    public let sourceName: String

    public init(id: UUID = UUID(), payload: ClipPayload, copiedAt: Date = Date(), sourceName: String = "") {
        self.id = id
        self.payload = payload
        self.copiedAt = copiedAt
        self.sourceName = sourceName
    }
}

public struct History {
    public private(set) var entries: [HistoryEntry] = []
    public let maxCount: Int
    public let maxBytes: Int
    public let maxItemBytes: Int

    public init(entries: [HistoryEntry] = [], maxCount: Int = 10,
                maxBytes: Int = .max, maxItemBytes: Int = 8 * 1024 * 1024) {
        self.maxCount = max(1, maxCount)
        self.maxBytes = max(1, maxBytes)
        self.maxItemBytes = max(1, maxItemBytes)
        for entry in entries.reversed() { insert(entry) }
    }

    @discardableResult
    public mutating func insert(_ entry: HistoryEntry) -> Bool {
        guard entry.payload.isValid, entry.payload.byteCount <= maxItemBytes,
              entry.payload.byteCount <= maxBytes else { return false }
        if entries.first?.payload == entry.payload { return false }
        entries.removeAll { $0.payload == entry.payload || $0.id == entry.id }
        entries.insert(entry, at: 0)
        var bytes = 0
        entries = Array(entries.prefix(maxCount).prefix { entry in
            bytes += entry.payload.byteCount
            return bytes <= maxBytes
        })
        return true
    }

    public mutating func remove(id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clear() { entries.removeAll() }

    public func matching(_ query: String) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.payload.searchableText.localizedStandardContains(query)
                || $0.sourceName.localizedStandardContains(query)
        }
    }
}

public struct HistoryStorage {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ entries: [HistoryEntry]) throws {
        try PrivateDataFile.write(JSONEncoder().encode(entries), to: fileURL)
    }
}

enum PrivateDataFile {
    static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    static func write(_ data: Data, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory(directory)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
