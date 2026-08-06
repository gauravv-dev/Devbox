import Foundation
import SwiftUI

/// JSON formatter/validator: format, minify, escape/unescape, with live validation.
struct JSONToolView: View {
    private enum IndentOption: String, CaseIterable, Identifiable {
        case twoSpaces = "2"
        case fourSpaces = "4"
        case tabs = "Tab"

        var id: String { rawValue }

        var string: String {
            switch self {
            case .twoSpaces: return "  "
            case .fourSpaces: return "    "
            case .tabs: return "\t"
            }
        }
    }

    @State private var input = ""
    @State private var output = ""
    @State private var indent: IndentOption = .twoSpaces
    @State private var sortedKeys = false

    var body: some View {
        ToolContainer(title: "JSON", subtitle: "Format, minify, escape, and validate JSON.") {
            VStack(spacing: 8) {
                toolbar
                if let validation {
                    StatusBadge(message: validation.message, isError: validation.isError)
                }
                VSplitView {
                    inputPane
                    outputPane
                }
            }
        }
    }

    // MARK: - Toolbar

    private var hasInput: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Indent", selection: $indent) {
                ForEach(IndentOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Toggle("Sorted keys", isOn: $sortedKeys)
                .toggleStyle(.checkbox)

            Spacer()

            ToolButton(title: "Format", systemImage: "increase.indent") { format() }
                .disabled(!hasInput)
            ToolButton(title: "Minify", systemImage: "decrease.indent") { minify() }
                .disabled(!hasInput)
            ToolButton(title: "Escape") { escape() }
                .disabled(!hasInput)
            ToolButton(title: "Unescape") { unescape() }
                .disabled(!hasInput)
            ToolButton(title: "Sample") { input = Self.sample }
            ToolButton(title: "Clear") { clear() }
        }
    }

    // MARK: - Panes

    private var inputPane: some View {
        VStack(spacing: 6) {
            PaneHeader(title: "Input") {
                OpenFileButton(text: $input)
            }
            CodeEditor(text: $input, placeholder: "Paste JSON…")
                .frame(minWidth: 320, minHeight: 160)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var outputPane: some View {
        VStack(spacing: 6) {
            PaneHeader(title: "Output", badge: output.isEmpty ? nil : "\(output.count) chars") {
                CopyButton(text: { output })
                SaveFileButton(text: { output }, filename: "formatted.json")
            }
            CodeEditor(text: $output, placeholder: "Output appears here", editable: false)
                .frame(minWidth: 320, minHeight: 160)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func parseInput() -> Any? {
        guard hasInput else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.allowFragments])
    }

    private func format() {
        guard let value = parseInput() else {
            output = ""
            return
        }
        output = JSONPrettyPrinter.print(value, indent: indent.string, sortedKeys: sortedKeys)
    }

    private func minify() {
        guard let value = parseInput() else {
            output = ""
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            output = String(data: data, encoding: .utf8) ?? ""
        } catch {
            output = ""
        }
    }

    private func escape() {
        output = "\"" + JSONPrettyPrinter.escaped(input) + "\""
    }

    private func unescape() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let fragment = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed]),
           let string = fragment as? String {
            output = string
        } else {
            output = JSONUnescaper.unescape(input)
        }
    }

    private func clear() {
        input = ""
        output = ""
    }

    // MARK: - Live validation

    private var validation: (message: String, isError: Bool)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let value = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.allowFragments])
            return ("Valid JSON · \(input.count) chars · depth \(JSONPrettyPrinter.depth(of: value))", false)
        } catch {
            return ("Invalid JSON: \(Self.describe(error))", true)
        }
    }

    private static func describe(_ error: Error) -> String {
        var message = error.localizedDescription
        let nsError = error as NSError
        if let debug = nsError.userInfo["NSDebugDescription"] as? String, !debug.isEmpty {
            message += " (\(debug))"
        }
        return message
    }

    private static let sample = """
    {
      "app": "Devbox",
      "version": 1,
      "stable": true,
      "tags": ["json", "formatter", "validator"],
      "settings": {
        "indent": 2,
        "sorted_keys": false
      }
    }
    """
}

// MARK: - Pretty printer

private enum JSONPrettyPrinter {
    static func print(_ value: Any, indent: String, sortedKeys: Bool) -> String {
        var out = ""
        emit(value, indent: indent, sortedKeys: sortedKeys, level: 0, into: &out)
        return out
    }

    /// Nesting depth: scalars are 1, containers are 1 + max child depth.
    static func depth(of value: Any) -> Int {
        if let dict = value as? [String: Any] {
            return 1 + (dict.values.map(depth).max() ?? 0)
        }
        if let array = value as? [Any] {
            return 1 + (array.map(depth).max() ?? 0)
        }
        return 1
    }

    /// Escapes a string for inclusion in a JSON string literal (without surrounding quotes).
    static func escaped(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for char in string {
            switch char {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1, scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.append(char)
                }
            }
        }
        return out
    }

    private static func emit(_ value: Any, indent: String, sortedKeys: Bool, level: Int, into out: inout String) {
        let pad = String(repeating: indent, count: level + 1)
        let closingPad = String(repeating: indent, count: level)

        if let dict = value as? [String: Any] {
            guard !dict.isEmpty else {
                out += "{}"
                return
            }
            let pairs = sortedKeys ? dict.sorted(by: { $0.key < $1.key }) : Array(dict)
            out += "{\n"
            for (index, pair) in pairs.enumerated() {
                out += pad
                out += "\"\(escaped(pair.key))\": "
                emit(pair.value, indent: indent, sortedKeys: sortedKeys, level: level + 1, into: &out)
                if index < pairs.count - 1 { out += "," }
                out += "\n"
            }
            out += closingPad + "}"
        } else if let array = value as? [Any] {
            guard !array.isEmpty else {
                out += "[]"
                return
            }
            out += "[\n"
            for (index, element) in array.enumerated() {
                out += pad
                emit(element, indent: indent, sortedKeys: sortedKeys, level: level + 1, into: &out)
                if index < array.count - 1 { out += "," }
                out += "\n"
            }
            out += closingPad + "]"
        } else if let string = value as? String {
            out += "\"\(escaped(string))\""
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                out += number.boolValue ? "true" : "false"
            } else {
                out += numberText(number)
            }
        } else if value is NSNull {
            out += "null"
        } else {
            out += "\"\(escaped(String(describing: value)))\""
        }
    }

    /// Renders a number, preserving integer-ness: whole doubles that fit Int64 drop the ".0".
    private static func numberText(_ number: NSNumber) -> String {
        let double = number.doubleValue
        if double.isFinite,
           double == double.rounded(.towardZero),
           double > -9.223372036854776e18,
           double < 9.223372036854776e18 {
            return String(Int64(double))
        }
        return number.description
    }
}

// MARK: - Naive unescaper

private enum JSONUnescaper {
    /// Fallback unescape of \" \\ \/ \n \t \r \b \f \uXXXX when the input is not a JSON string literal.
    static func unescape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        var index = string.startIndex
        while index < string.endIndex {
            let char = string[index]
            guard char == "\\" else {
                out.append(char)
                index = string.index(after: index)
                continue
            }
            let next = string.index(after: index)
            guard next < string.endIndex else {
                out.append(char)
                index = next
                continue
            }
            let escape = string[next]
            switch escape {
            case "\"":
                out.append("\"")
                index = string.index(after: next)
            case "\\":
                out.append("\\")
                index = string.index(after: next)
            case "/":
                out.append("/")
                index = string.index(after: next)
            case "n":
                out.append("\n")
                index = string.index(after: next)
            case "t":
                out.append("\t")
                index = string.index(after: next)
            case "r":
                out.append("\r")
                index = string.index(after: next)
            case "b":
                out.append("\u{08}")
                index = string.index(after: next)
            case "f":
                out.append("\u{0C}")
                index = string.index(after: next)
            case "u":
                let hexStart = string.index(after: next)
                guard let hexEnd = string.index(hexStart, offsetBy: 4, limitedBy: string.endIndex),
                      let code = UInt32(String(string[hexStart..<hexEnd]), radix: 16) else {
                    out.append(char)
                    out.append(escape)
                    index = string.index(after: next)
                    continue
                }
                // Combine surrogate pairs into a single scalar.
                if (0xD800...0xDBFF).contains(code),
                   let low = unicodeEscapeValue(in: string, at: hexEnd),
                   (0xDC00...0xDFFF).contains(low),
                   let scalar = Unicode.Scalar(0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)) {
                    out.append(Character(scalar))
                    index = string.index(hexEnd, offsetBy: 6)
                    continue
                }
                if let scalar = Unicode.Scalar(code) {
                    out.append(Character(scalar))
                    index = hexEnd
                } else {
                    out.append(char)
                    out.append(escape)
                    index = string.index(after: next)
                }
            default:
                out.append(char)
                out.append(escape)
                index = string.index(after: next)
            }
        }
        return out
    }

    /// Reads a "\uXXXX" sequence starting at `index`, returning its hex value.
    private static func unicodeEscapeValue(in string: String, at index: String.Index) -> UInt32? {
        guard index < string.endIndex, string[index] == "\\" else { return nil }
        let second = string.index(after: index)
        guard second < string.endIndex, string[second] == "u" else { return nil }
        let start = string.index(after: second)
        guard let end = string.index(start, offsetBy: 4, limitedBy: string.endIndex), end > start else { return nil }
        return UInt32(String(string[start..<end]), radix: 16)
    }
}
