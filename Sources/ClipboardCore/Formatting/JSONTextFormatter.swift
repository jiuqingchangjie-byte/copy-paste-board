import Foundation

/// Validates JSON grammar and changes only whitespace outside tokens. Numbers,
/// escaped strings, duplicate keys and member order never pass through a value
/// decoder, so formatting cannot round IDs or silently drop object members.
public enum JSONTextFormatter {
    public static let maximumInputBytes = 8 * 1024 * 1024
    public static let maximumOutputBytes = 32 * 1024 * 1024
    public static let maximumDepth = 128

    public static func format(_ text: String) throws -> String {
        guard text.utf8.count <= maximumInputBytes else {
            throw JSONFormattingError(reason: "内容超过 8 MiB，无法格式化", line: 1, column: 1)
        }
        var parser = JSONWhitespaceParser(text)
        return try parser.format()
    }
}

public struct JSONFormattingError: LocalizedError, Equatable {
    public let reason: String
    public let line: Int
    public let column: Int
    public var errorDescription: String? { "第 \(line) 行，第 \(column) 列：\(reason)" }
}

private struct JSONWhitespaceParser {
    private let bytes: [UInt8]
    private var index = 0
    private var output: [UInt8] = []

    init(_ text: String) {
        bytes = Array(text.utf8)
        output.reserveCapacity(min(bytes.count, JSONTextFormatter.maximumOutputBytes))
    }

    mutating func format() throws -> String {
        skipWhitespace()
        try value(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw failure("JSON 结束后存在多余内容") }
        return String(decoding: output, as: UTF8.self)
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }
    private func isDigit(_ byte: UInt8?) -> Bool { byte.map { (48...57).contains($0) } ?? false }
    private mutating func skipWhitespace() {
        while let byte = current, byte == 32 || byte == 9 || byte == 10 || byte == 13 { index += 1 }
    }

    private mutating func append(_ byte: UInt8) throws {
        guard output.count < JSONTextFormatter.maximumOutputBytes else { throw failure("格式化结果过大，请缩小内容后重试") }
        output.append(byte)
    }

    private mutating func appendToken(from start: Int) throws {
        guard index - start <= JSONTextFormatter.maximumOutputBytes - output.count else {
            throw failure("格式化结果过大，请缩小内容后重试")
        }
        output.append(contentsOf: bytes[start..<index])
    }

    private mutating func newline(depth: Int) throws {
        try append(10)
        for _ in 0..<(depth * 2) { try append(32) }
    }

    private mutating func value(depth: Int) throws {
        skipWhitespace()
        guard let byte = current else { throw failure("此处需要 JSON 值") }
        switch byte {
        case 123, 91: try container(depth: depth)
        case 34: try string()
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        case 45, 48...57: try number()
        default: throw failure("此处需要 JSON 值")
        }
    }

    private mutating func container(depth: Int) throws {
        guard depth < JSONTextFormatter.maximumDepth else { throw failure("嵌套超过 128 层，无法格式化") }
        let isObject = current == 123
        let close: UInt8 = isObject ? 125 : 93
        try append(bytes[index])
        index += 1
        skipWhitespace()
        if current == close { try append(close); index += 1; return }
        try newline(depth: depth + 1)
        while true {
            if isObject {
                guard current == 34 else { throw failure("对象键必须使用双引号") }
                try string()
                skipWhitespace()
                guard current == 58 else { throw failure("对象键后缺少冒号") }
                index += 1
                try append(58)
                try append(32)
            }
            try value(depth: depth + 1)
            skipWhitespace()
            if current == close {
                index += 1
                try newline(depth: depth)
                try append(close)
                return
            }
            guard current == 44 else { throw failure(isObject ? "此处需要逗号或 }" : "此处需要逗号或 ]") }
            index += 1
            try append(44)
            try newline(depth: depth + 1)
            skipWhitespace()
            // The next iteration requires a real key/value, rejecting trailing commas.
        }
    }

    private mutating func string() throws {
        let start = index
        index += 1
        while let byte = current {
            if byte == 34 { index += 1; try appendToken(from: start); return }
            guard byte >= 32 else { throw failure("字符串中包含未转义的控制字符") }
            index += 1
            if byte == 92 {
                guard let escape = current else { throw failure("字符串转义不完整") }
                index += 1
                switch escape {
                case 34, 92, 47, 98, 102, 110, 114, 116: break
                case 117:
                    for _ in 0..<4 {
                        guard let hex = current,
                              (48...57).contains(hex) || (65...70).contains(hex) || (97...102).contains(hex) else {
                            throw failure("Unicode 转义需要四位十六进制字符")
                        }
                        index += 1
                    }
                default: throw failure("无效的字符串转义")
                }
            }
        }
        throw failure("字符串缺少结束双引号")
    }

    private mutating func number() throws {
        let start = index
        if current == 45 { index += 1 }
        guard isDigit(current) else { throw failure("负号后缺少数字") }
        if current == 48 { index += 1 }
        else { while isDigit(current) { index += 1 } }
        if current == 46 {
            index += 1
            guard isDigit(current) else { throw failure("小数点后缺少数字") }
            while isDigit(current) { index += 1 }
        }
        if current == 101 || current == 69 {
            index += 1
            if current == 43 || current == 45 { index += 1 }
            guard isDigit(current) else { throw failure("指数部分缺少数字") }
            while isDigit(current) { index += 1 }
        }
        try appendToken(from: start)
    }

    private mutating func literal(_ value: StaticString) throws {
        let start = index
        for byte in String(describing: value).utf8 {
            guard current == byte else { throw failure("无效的 JSON 值") }
            index += 1
        }
        try appendToken(from: start)
    }

    private func failure(_ reason: String) -> JSONFormattingError {
        // Count displayed Unicode scalars rather than UTF-8 bytes; CRLF is one line break.
        let prefix = String(decoding: bytes.prefix(index), as: UTF8.self)
        var line = 1, column = 1
        var wasCR = false
        for scalar in prefix.unicodeScalars {
            if scalar.value == 13 { line += 1; column = 1 }
            else if scalar.value == 10 { if !wasCR { line += 1 }; column = 1 }
            else { column += 1 }
            wasCR = scalar.value == 13
        }
        return JSONFormattingError(reason: reason, line: line, column: column)
    }
}
