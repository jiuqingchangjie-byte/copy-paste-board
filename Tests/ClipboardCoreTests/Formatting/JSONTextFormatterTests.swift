import Foundation
import Testing
@testable import ClipboardCore

struct JSONTextFormatterTests {
    @Test func formatsNestedObjectsArraysAndEmptyContainers() throws {
        let source = #" {"b":[1,true,null,{"a":"杭州😀"}],"empty":{},"arr":[]} "#
        let expected = """
        {
          "b": [
            1,
            true,
            null,
            {
              "a": "杭州😀"
            }
          ],
          "empty": {},
          "arr": []
        }
        """
        #expect(try JSONTextFormatter.format(source) == expected)
        #expect(try JSONTextFormatter.format(expected) == expected)
    }

    @Test func preservesNumberLexemesDuplicateKeysOrderAndEscapedStrings() throws {
        let source = #"{"z":900719925474099312345678901234567890,"z":-0,"decimal":1.2300000000000000000000000000000000000001,"huge":1E+9999,"tiny":-1e-9999,"s":"\\ \" \/ \b \f \n \r \t \u4e2d \uD83D\uDE00 {,}:"}"#
        let formatted = try JSONTextFormatter.format(source)
        #expect(tokens(formatted) == tokens(source))
        #expect(formatted.components(separatedBy: #""z":"#).count == 3)
        #expect(formatted.contains("900719925474099312345678901234567890"))
        #expect(formatted.contains("1.2300000000000000000000000000000000000001"))
    }

    @Test(arguments: ["true", "false", "null", "-0", "0.00", "42", "1e+10000", #""hello 😀""#, "[]", "{}"])
    func acceptsTopLevelValues(_ value: String) throws {
        #expect(try JSONTextFormatter.format("\r\n\t " + value + " \n") == value)
    }

    @Test(arguments: ["", " ", "SELECT *", "{'a':1}", "{a:1}", "{\"a\" 1}", "{\"a\":}",
        "{\"a\":1,}", "[1,]", "[,1]", "[1 2]", "{} []", "true false", "TRUE", "NaN", "Infinity",
        "01", "-01", "+1", "1.", ".1", "1e", "1e+", "-", "00", "falsee", "nul", "[", "{", "[}",
        "\"unclosed", "\"line\nbreak\"", "\"\u{0000}\"", #""\x""#, #""\u123""#, #""\uZZZZ""#,
        "//comment\n{}", "/*comment*/{}", "\u{FEFF}{}"])
    func rejectsInvalidJSON(_ source: String) {
        #expect(throws: JSONFormattingError.self) { try JSONTextFormatter.format(source) }
    }

    @Test func reportsUnicodeColumnsAndCRLFAsOneLineBreak() throws {
        do {
            _ = try JSONTextFormatter.format("{\r\n  \"😀\": invalid}")
            Issue.record("Invalid JSON was accepted")
        } catch let error as JSONFormattingError {
            #expect(error.line == 2)
            #expect(error.column == 8)
        }
    }

    @Test func boundsInputDepthAndExpandedOutputWithoutCrashing() throws {
        let depth = JSONTextFormatter.maximumDepth
        let valid = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
        #expect(!((try JSONTextFormatter.format(valid)).isEmpty))
        #expect(throws: JSONFormattingError.self) { try JSONTextFormatter.format("[" + valid + "]") }
        let atLimit = "\"" + String(repeating: "a", count: JSONTextFormatter.maximumInputBytes - 2) + "\""
        #expect(try JSONTextFormatter.format(atLimit) == atLimit)
        #expect(throws: JSONFormattingError.self) { try JSONTextFormatter.format(atLimit + " ") }
        let expansion = String(repeating: "[", count: depth) + Array(repeating: "0", count: 140_000).joined(separator: ",") + String(repeating: "]", count: depth)
        #expect(throws: JSONFormattingError.self) { try JSONTextFormatter.format(expansion) }
    }

    @Test func generatedDocumentsMatchIndependentDecoderAndAreIdempotent() throws {
        for index in 0..<150 {
            let value: [String: Any] = ["index": index, "text": "row \(index) 😀\n\"\\", "values": [true, NSNull(), ["nested": index]], "empty": [Any]()]
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            let source = String(decoding: data, as: UTF8.self)
            let pretty = try JSONTextFormatter.format(source)
            #expect(tokens(pretty) == tokens(source))
            let decoded = try JSONSerialization.jsonObject(with: Data(pretty.utf8)) as? NSDictionary
            #expect(decoded == value as NSDictionary)
            #expect(try JSONTextFormatter.format(pretty) == pretty)
        }
    }

    /// Independent whitespace stripping oracle that never removes string spaces.
    private func tokens(_ text: String) -> [UInt8] {
        var inString = false, escaped = false
        return text.utf8.filter { byte in
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
                return true
            }
            if byte == 34 { inString = true }
            return ![9, 10, 13, 32].contains(byte)
        }
    }
}
