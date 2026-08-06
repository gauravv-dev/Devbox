import SwiftUI
import AppKit
import Foundation

private let regexMatchCap = 500
private let regexHighlightCharLimit = 100_000

private struct RegexMatchItem: Identifiable {
    let id: Int
    let text: String
    let start: Int
    let end: Int
    let groups: [RegexGroupCapture]
}

private struct RegexGroupCapture: Identifiable {
    let index: Int
    let text: String?

    var id: Int { index }
}

private struct RegexEval {
    var regex: NSRegularExpression?
    var errorMessage: String?
    var matches: [RegexMatchItem] = []
    var truncated = false
    var highlighted: AttributedString?
    var replaced = ""

    var countLabel: String {
        if truncated { return "\(regexMatchCap)+ matches" }
        let n = matches.count
        return "\(n) \(n == 1 ? "match" : "matches")"
    }
}

/// Live NSRegularExpression tester: pattern with flag toggles, match list with
/// capture groups, a highlighted preview, and template-based replacement.
struct RegexToolView: View {
    @State private var pattern = ""
    @State private var input = ""
    @State private var template = ""
    @State private var caseInsensitive = false
    @State private var multiline = false
    @State private var dotMatchesAll = false
    @State private var ignoreWhitespace = false
    @State private var showCheatsheet = false

    var body: some View {
        ToolContainer(title: "Regex Tester",
                      subtitle: "Test regular expressions live: matches, capture groups, highlighting, and replacement.") {
            let eval = evaluate()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    patternSection(eval)
                    inputSection
                    if let highlighted = eval.highlighted {
                        highlightSection(highlighted)
                    }
                    if eval.regex != nil, !input.isEmpty {
                        matchesSection(eval)
                    }
                    if eval.regex != nil {
                        replaceSection(eval)
                    }
                    cheatsheet
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Sections

    private func patternSection(_ eval: RegexEval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Pattern…", text: $pattern)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 16) {
                Toggle("Case insensitive (i)", isOn: $caseInsensitive)
                Toggle("Multiline (m)", isOn: $multiline)
                Toggle("Dot matches all (s)", isOn: $dotMatchesAll)
                Toggle("Ignore whitespace (x)", isOn: $ignoreWhitespace)
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            if let errorMessage = eval.errorMessage {
                StatusBadge(message: errorMessage, isError: true)
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Test String", badge: input.isEmpty ? nil : "\(input.count) chars") {
                OpenFileButton(text: $input)
                CopyButton(text: { input })
            }
            CodeEditor(text: $input, placeholder: "Test string…")
                .frame(height: 220)
        }
    }

    private func highlightSection(_ highlighted: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Highlight Preview").font(.headline)
            Text(highlighted)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.25)))
        }
    }

    private func matchesSection(_ eval: RegexEval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Matches", badge: eval.countLabel) {
                CopyButton(text: { eval.matches.map(\.text).joined(separator: "\n") }, label: "Copy All")
            }
            if eval.matches.isEmpty {
                Text("No matches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(eval.matches) { MatchRowView(match: $0) }
                }
                if eval.truncated {
                    Text("Showing the first \(regexMatchCap) matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func replaceSection(_ eval: RegexEval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Replace") {
                CopyButton(text: { eval.replaced })
                SaveFileButton(text: { eval.replaced }, filename: "replaced.txt")
            }
            TextField("Replacement template — $0 whole match, $1…$9 groups", text: $template)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            CodeEditor(text: .constant(eval.replaced), placeholder: "Replacement result…", editable: false)
                .frame(height: 140)
            Text("NSRegularExpression template syntax: $1, $2 … reference capture groups. An empty template removes all matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cheatsheet: some View {
        DisclosureGroup("Cheatsheet", isExpanded: $showCheatsheet) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      spacing: 6) {
                ForEach(Self.cheatsheetEntries.indices, id: \.self) { index in
                    let entry = Self.cheatsheetEntries[index]
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.0)
                            .font(.system(size: 12, design: .monospaced).bold())
                            .frame(width: 64, alignment: .leading)
                        Text(entry.1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(.callout)
    }

    private static let cheatsheetEntries: [(String, String)] = [
        (".", "any character"),
        ("\\d / \\D", "digit / non-digit"),
        ("\\w / \\W", "word char / non-word char"),
        ("\\s / \\S", "whitespace / non-whitespace"),
        ("^ / $", "start / end of line"),
        ("\\b", "word boundary"),
        ("*", "0 or more"),
        ("+", "1 or more"),
        ("?", "0 or 1, or lazy"),
        ("{n,m}", "between n and m times"),
        ("[abc]", "character class"),
        ("[^abc]", "negated class"),
        ("(abc)", "capture group"),
        ("(?:abc)", "non-capturing group"),
        ("a|b", "alternation"),
        ("$1, $2", "group refs in templates"),
    ]

    // MARK: - Evaluation

    private func evaluate() -> RegexEval {
        var eval = RegexEval()
        guard !pattern.isEmpty else { return eval }

        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if multiline { options.insert(.anchorsMatchLines) }
        if dotMatchesAll { options.insert(.dotMatchesLineSeparators) }
        if ignoreWhitespace { options.insert(.allowCommentsAndWhitespace) }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            eval.errorMessage = Self.describePatternError(error)
            return eval
        }
        eval.regex = regex
        guard !input.isEmpty else { return eval }

        let fullRange = NSRange(input.startIndex..<input.endIndex, in: input)
        var matchedRanges: [NSRange] = []
        regex.enumerateMatches(in: input, options: [], range: fullRange) { result, _, stop in
            guard let result else { return }
            if eval.matches.count < regexMatchCap {
                eval.matches.append(Self.makeMatch(result, id: eval.matches.count, in: input))
                matchedRanges.append(result.range)
            } else {
                eval.truncated = true
                stop.pointee = true
            }
        }

        if input.count <= regexHighlightCharLimit {
            eval.highlighted = Self.highlightedText(input, ranges: matchedRanges)
        }

        eval.replaced = regex.stringByReplacingMatches(in: input, options: [], range: fullRange, withTemplate: template)
        return eval
    }

    private static func makeMatch(_ result: NSTextCheckingResult, id: Int, in text: String) -> RegexMatchItem {
        let range = result.range
        var groups: [RegexGroupCapture] = []
        for i in 1..<result.numberOfRanges {
            let groupRange = result.range(at: i)
            if groupRange.location == NSNotFound {
                groups.append(RegexGroupCapture(index: i, text: nil))
            } else {
                groups.append(RegexGroupCapture(index: i, text: substring(groupRange, in: text) ?? ""))
            }
        }
        return RegexMatchItem(
            id: id,
            text: substring(range, in: text) ?? "",
            start: range.location,
            end: range.location + range.length,
            groups: groups)
    }

    private static func substring(_ range: NSRange, in text: String) -> String? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// Builds a read-only highlighted preview: matched ranges get a yellow background.
    private static func highlightedText(_ text: String, ranges: [NSRange]) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for nsRange in ranges {
            guard let range = Range(nsRange, in: text), range.lowerBound >= cursor else { continue }
            if range.lowerBound > cursor {
                result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            }
            if !range.isEmpty {
                var match = AttributedString(String(text[range]))
                match.backgroundColor = Color.yellow.opacity(0.4)
                result.append(match)
            }
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result.append(AttributedString(String(text[cursor...])))
        }
        result.font = .system(size: 13, design: .monospaced)
        return result
    }

    private static func describePatternError(_ error: Error) -> String {
        let nsError = error as NSError
        var message = nsError.localizedDescription
        if message.isEmpty { message = "Invalid regular expression." }
        // Surface the parse-error offset/range when Foundation provides one.
        for (key, value) in nsError.userInfo where !(value is String) {
            let name = String(describing: key).lowercased()
            if name.contains("offset") || name.contains("range"), let number = value as? NSNumber {
                message += " (offset \(number.intValue))"
            }
        }
        return message
    }
}

private struct MatchRowView: View {
    let match: RegexMatchItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(match.id + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(display(match.text, emptyLabel: "(empty match)"))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer()
                Text("\(match.start)–\(match.end)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ForEach(match.groups) { group in
                Text("$\(group.index) = \(group.text.map { display($0, emptyLabel: "(empty)") } ?? "nil")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(group.text == nil ? Color.secondary.opacity(0.6) : Color.primary.opacity(0.8))
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
    }

    private func display(_ text: String, emptyLabel: String) -> String {
        if text.isEmpty { return emptyLabel }
        let compact = text.replacingOccurrences(of: "\n", with: "⏎")
        if compact.count > 400 { return String(compact.prefix(400)) + "…" }
        return compact
    }
}
