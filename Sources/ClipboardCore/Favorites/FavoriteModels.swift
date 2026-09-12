import Foundation

public struct FavoriteFolder: Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let count: Int
}
public enum FavoriteScope: Equatable {
    case all, unfiled, folder(UUID)
}
public struct FavoriteSummary: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let kind: String
    public let source: String
    public let folderID: UUID?
    public let thumbnail: Data?
}
public struct FavoritePage {
    public let items: [FavoriteSummary]
    public let total: Int
}
