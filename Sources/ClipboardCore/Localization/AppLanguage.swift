import Foundation

public enum AppLanguage: String, Codable, CaseIterable {
    case chinese = "zh-Hans", english = "en", japanese = "ja", korean = "ko"

    /// Always shown in each language's own script, so users can recover from a mistaken choice.
    public var nativeName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    public var locale: Locale { Locale(identifier: rawValue) }
    public static func preferred(from identifiers: [String]) -> Self {
        for identifier in identifiers {
            switch identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first {
            case "zh": return .chinese
            case "en": return .english
            case "ja": return .japanese
            case "ko": return .korean
            default: continue
            }
        }
        return .english
    }
}

public enum L10n {
    private static let lock = NSLock()
    private static var selected: AppLanguage = .chinese
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); defer { lock.unlock() }; selected = newValue }
    }
    public static func tr(_ key: String, _ arguments: String...) -> String {
        text(key, language: language, arguments: arguments)
    }
    /// Only for app-owned status text, never clipboard text or user folder names.
    public static func relocalizeAppText(_ text: String) -> String {
        if catalog[text] != nil { return tr(text) }
        if let key = catalog.first(where: { $0.value.contains(text) })?.key { return tr(key) }
        return text
    }
    public static func sourceName(_ source: String) -> String {
        for key in ["收藏库", "收藏预览", "剪贴板预览"] {
            if source == key || catalog[key]?.contains(source) == true { return tr(key) }
        }
        return source
    }
    public static func text(_ key: String, language: AppLanguage, arguments: [String] = []) -> String {
        let index: Int
        switch language {
        case .chinese: index = -1
        case .english: index = 0
        case .japanese: index = 1
        case .korean: index = 2
        }
        let template = index < 0 ? key : catalog[key]?[index] ?? key
        // Replace in one pass: user content containing {1} or percent signs is never reinterpreted.
        let regex = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        let source = template as NSString
        var result = "", cursor = 0
        for match in regex.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = Int(source.substring(with: match.range(at: 1)))!
            result += arguments.indices.contains(index) ? arguments[index] : source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        return result + source.substring(from: cursor)
    }
}
