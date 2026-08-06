import SwiftUI
import AppKit
import Foundation

/// All transforms offered by TextToolView, applied live to the input.
private enum TextOperation: String, CaseIterable, Identifiable {
    // Case conversions
    case upper = "UPPERCASE"
    case lower = "lowercase"
    case title = "Title Case"
    case sentence = "Sentence case"
    case camel = "camelCase"
    case pascal = "PascalCase"
    case snake = "snake_case"
    case screaming = "SCREAMING_SNAKE"
    case kebab = "kebab-case"
    case dot = "dot.case"
    // Other transforms
    case reverse = "Reverse"
    case reverseLines = "Reverse Lines"
    case sortAscending = "Sort Lines Ascending"
    case sortDescending = "Sort Lines Descending"
    case removeDuplicateLines = "Remove Duplicate Lines"
    case removeEmptyLines = "Remove Empty Lines"
    case trimLines = "Trim Whitespace"
    case trimAll = "Trim All"
    case urlSlug = "URL Slug"
    case escapeJSON = "Escape JSON String"
    case unescapeJSON = "Unescape JSON String"

    var id: String { rawValue }

    var isCaseConversion: Bool {
        switch self {
        case .upper, .lower, .title, .sentence, .camel, .pascal, .snake, .screaming, .kebab, .dot:
            return true
        default:
            return false
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .title:
            return Self.splitWords(text).map(Self.capitalize).joined(separator: " ")
        case .sentence:
            return Self.sentenceCase(text)
        case .camel:
            let words = Self.splitWords(text)
            guard let first = words.first else { return "" }
            return first.lowercased() + words.dropFirst().map(Self.capitalize).joined()
        case .pascal:
            return Self.splitWords(text).map(Self.capitalize).joined()
        case .snake:
            return Self.splitWords(text).map { $0.lowercased() }.joined(separator: "_")
        case .screaming:
            return Self.splitWords(text).map { $0.uppercased() }.joined(separator: "_")
        case .kebab:
            return Self.splitWords(text).map { $0.lowercased() }.joined(separator: "-")
        case .dot:
            return Self.splitWords(text).map { $0.lowercased() }.joined(separator: ".")
        case .reverse:
            return String(text.reversed())
        case .reverseLines:
            return text.components(separatedBy: "\n").reversed().joined(separator: "\n")
        case .sortAscending:
            return text.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .sortDescending:
            return text.components(separatedBy: "\n").sorted(by: >).joined(separator: "\n")
        case .removeDuplicateLines:
            var seen = Set<String>()
            return text.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .removeEmptyLines:
            return text.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
        case .trimLines:
            return text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        case .trimAll:
            return text.components(separatedBy: "\n")
                .map { line in
                    line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                }
                .joined(separator: "\n")
        case .urlSlug:
            return Self.urlSlug(text)
        case .escapeJSON:
            return Self.escapeJSON(text)
        case .unescapeJSON:
            return Self.unescapeJSON(text)
        }
    }

    // MARK: - Word splitting

    /// Splits on whitespace and `_- .`, plus case transitions:
    /// `someHTTPValue` → `some`, `HTTP`, `Value`.
    static func splitWords(_ text: String) -> [String] {
        let chars = Array(text)

        func isSeparator(_ c: Character) -> Bool {
            c.isWhitespace || c == "_" || c == "-" || c == "."
        }

        var words: [String] = []
        var current: [Character] = []

        func flush() {
            if !current.isEmpty {
                words.append(String(current))
                current = []
            }
        }

        for (i, c) in chars.enumerated() {
            if isSeparator(c) {
                flush()
                continue
            }
            if i > 0, !isSeparator(chars[i - 1]) {
                let prev = chars[i - 1]
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                let boundary = (c.isUppercase && prev.isLowercase)
                    || (c.isUppercase && prev.isUppercase && next?.isLowercase == true)
                    || (c.isNumber != prev.isNumber)
                if boundary { flush() }
            }
            current.append(c)
        }
        flush()
        return words
    }

    /// Capitalize = first letter upper, rest lower.
    static func capitalize(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }

    static func sentenceCase(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var capitalizeNext = true
        for c in text {
            if c.isLetter {
                out.append(capitalizeNext ? c.uppercased() : c.lowercased())
                capitalizeNext = false
            } else {
                out.append(c)
                if c == "." || c == "!" || c == "?" {
                    capitalizeNext = true
                }
            }
        }
        return out
    }

    static func urlSlug(_ text: String) -> String {
        var slug = ""
        var pendingDash = false
        for c in text.lowercased() {
            if c.isLetter || c.isNumber {
                if pendingDash && !slug.isEmpty { slug.append("-") }
                slug.append(c)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return slug
    }

    static func escapeJSON(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for c in text {
            switch c {
            case "\\": out.append("\\\\")
            case "\"": out.append("\\\"")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\u{0C}": out.append("\\f")
            default:
                if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1, scalar.value < 0x20 {
                    out.append(String(format: "\\u%04x", scalar.value))
                } else {
                    out.append(c)
                }
            }
        }
        return out
    }

    static func unescapeJSON(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var idx = text.startIndex

        func readHex(from start: String.Index, count: Int) -> (UInt32, String.Index)? {
            guard let end = text.index(start, offsetBy: count, limitedBy: text.endIndex), end <= text.endIndex else { return nil }
            let hex = String(text[start..<end])
            guard hex.count == count, let value = UInt32(hex, radix: 16) else { return nil }
            return (value, end)
        }

        while idx < text.endIndex {
            let c = text[idx]
            guard c == "\\" else {
                out.append(c)
                idx = text.index(after: idx)
                continue
            }
            let escIdx = text.index(after: idx)
            guard escIdx < text.endIndex else {
                out.append(c)
                break
            }
            switch text[escIdx] {
            case "n": out.append("\n"); idx = text.index(after: escIdx)
            case "t": out.append("\t"); idx = text.index(after: escIdx)
            case "r": out.append("\r"); idx = text.index(after: escIdx)
            case "b": out.append("\u{08}"); idx = text.index(after: escIdx)
            case "f": out.append("\u{0C}"); idx = text.index(after: escIdx)
            case "\"": out.append("\""); idx = text.index(after: escIdx)
            case "\\": out.append("\\"); idx = text.index(after: escIdx)
            case "/": out.append("/"); idx = text.index(after: escIdx)
            case "u":
                let hexStart = text.index(after: escIdx)
                guard let (value, afterHex) = readHex(from: hexStart, count: 4) else {
                    out.append("\\u")
                    idx = hexStart
                    break
                }
                if (0xD800...0xDBFF).contains(value),
                   afterHex < text.endIndex, text[afterHex] == "\\",
                   text.index(after: afterHex) < text.endIndex, text[text.index(after: afterHex)] == "u",
                   let (low, afterLow) = readHex(from: text.index(afterHex, offsetBy: 2), count: 4),
                   (0xDC00...0xDFFF).contains(low) {
                    let code = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                    out.append(Unicode.Scalar(code).map(Character.init) ?? "\u{FFFD}")
                    idx = afterLow
                } else if let scalar = Unicode.Scalar(value) {
                    out.append(Character(scalar))
                    idx = afterHex
                } else {
                    out.append("\u{FFFD}")
                    idx = afterHex
                }
            default:
                // Unknown escape: keep it verbatim.
                out.append("\\")
                out.append(text[escIdx])
                idx = text.index(after: escIdx)
            }
        }
        return out
    }
}

/// Text transforms suite: case conversions, line operations, trimming, slugs,
/// and JSON string escaping — all applied live to the input.
struct TextToolView: View {
    @State private var input = ""
    @State private var operation: TextOperation = .camel

    private var output: String {
        operation.apply(to: input)
    }

    var body: some View {
        ToolContainer(title: "Text Transforms",
                      subtitle: "Case conversions, line operations, trimming, slugs, and JSON escaping — applied live.") {
            VStack(alignment: .leading, spacing: 12) {
                HSplitView {
                    inputPane
                    outputPane
                }
                controls
                statistics
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Panes

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Input", badge: input.isEmpty ? nil : "\(input.count) chars") {
                OpenFileButton(text: $input)
                CopyButton(text: { input })
            }
            CodeEditor(text: $input, placeholder: "Paste or type text…")
                .frame(minWidth: 320, minHeight: 200)
        }
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Output", badge: operation.rawValue) {
                CopyButton(text: { output })
                SaveFileButton(text: { output }, filename: "transformed.txt")
            }
            CodeEditor(text: .constant(output), placeholder: "Transformed text…", editable: false)
                .frame(minWidth: 320, minHeight: 200)
            StatusBadge(message: outputCountsLabel)
        }
    }

    private var outputCountsLabel: String {
        "\(output.count) chars · \(wordCount(output)) words · \(lineCount(output)) lines"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Operation", selection: $operation) {
                Section("Case") {
                    ForEach(TextOperation.allCases.filter(\.isCaseConversion)) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
                Section("Lines & Other") {
                    ForEach(TextOperation.allCases.filter { !$0.isCaseConversion }) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            if !input.isEmpty {
                Text("Live: edits re-apply \(operation.rawValue).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Statistics").font(.headline)
            Text(statisticsLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var statisticsLabel: String {
        let chars = input.count
        let charsNoSpaces = input.filter { !$0.isWhitespace }.count
        let words = wordCount(input)
        let lines = lineCount(input)
        let sentences = input.filter { $0 == "." || $0 == "!" || $0 == "?" }.count
        let paragraphs = input.isEmpty
            ? 0
            : input.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return "Characters: \(chars)    Characters (no spaces): \(charsNoSpaces)    Words: \(words)\nLines: \(lines)    Sentences (approx): \(sentences)    Paragraphs: \(paragraphs)"
    }

    // MARK: - Counting helpers

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func lineCount(_ text: String) -> Int {
        text.isEmpty ? 0 : text.components(separatedBy: "\n").count
    }
}
