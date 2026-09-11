import Foundation

/// Shared validation for persisted preferences and the preferences editor.
public struct PreviewSettings: Codable, Equatable {
    public static let delayRange = 0.2...5.0
    public var hoverEnabled: Bool
    public private(set) var hoverDelay: TimeInterval

    public init(hoverEnabled: Bool = true, hoverDelay: TimeInterval = 1) {
        self.hoverEnabled = hoverEnabled
        self.hoverDelay = hoverDelay.isFinite
            ? min(max(hoverDelay, Self.delayRange.lowerBound), Self.delayRange.upperBound) : 1
    }

    private enum CodingKeys: String, CodingKey { case hoverEnabled, hoverDelay }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hoverEnabled: try values.decodeIfPresent(Bool.self, forKey: .hoverEnabled) ?? true,
                  hoverDelay: try values.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? 1)
    }
}
