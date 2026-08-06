import SwiftUI
import Foundation

/// URL percent-encoder/decoder with component and full-URL modes, live transform,
/// and a structural breakdown when the input looks like a full URL.
struct URLToolView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case encode = "Encode"
        case decode = "Decode"
        var id: String { rawValue }
    }

    @State private var direction: Direction = .encode
    @State private var fullURLMode = false
    @State private var plusMeansSpace = false
    @State private var input = ""

    var body: some View {
        ToolContainer(title: "URL Encode",
                      subtitle: "Percent-encode and decode URLs and individual components") {
            VStack(alignment: .leading, spacing: 12) {
                controls
                inputPane
                outputPane
                if let breakdown = urlBreakdown {
                    breakdownPane(breakdown)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Panes

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Direction", selection: $direction) {
                ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            if direction == .encode {
                Toggle("Encode as full URL", isOn: $fullURLMode)
                    .toggleStyle(.checkbox)
                    .help(fullURLMode
                          ? "Keeps scheme, separators, and structure intact"
                          : "Escapes everything except RFC 3986 unreserved characters")
            } else {
                Toggle("'+' means space (form data)", isOn: $plusMeansSpace)
                    .toggleStyle(.checkbox)
            }

            Spacer()
        }
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: direction == .encode ? "Input" : "Input (percent-encoded)") {
                OpenFileButton(text: $input)
                ToolButton(title: "Clear", systemImage: "trash") { input = "" }
            }
            CodeEditor(text: $input,
                       placeholder: direction == .encode
                           ? "Type text or a URL to encode…"
                           : "Paste a percent-encoded URL or value…")
                .frame(minHeight: 120)
        }
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Output", badge: outputBadge) {
                CopyButton(text: { output.text })
                SaveFileButton(text: { output.text },
                               filename: direction == .encode ? "encoded-url.txt" : "decoded-url.txt")
            }
            CodeEditor(text: .constant(output.text), editable: false)
                .frame(minHeight: 120)
            if let error = output.error {
                StatusBadge(message: error, isError: true)
            } else if !output.text.isEmpty {
                StatusBadge(message: direction == .encode ? "Encoded" : "Decoded", isError: false)
            }
        }
    }

    private var outputBadge: String? {
        output.text.isEmpty ? nil : "\(output.text.count) chars"
    }

    // MARK: - URL breakdown

    private struct URLBreakdown {
        var scheme: String? = nil
        var user: String? = nil
        var host: String? = nil
        var port: Int? = nil
        var path: String? = nil
        var fragment: String? = nil
        var queryItems: [(name: String, value: String)] = []
    }

    /// Non-nil when the input parses as a URL with a host (or at least a scheme).
    private var urlBreakdown: URLBreakdown? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.host != nil || components.scheme != nil else { return nil }

        var breakdown = URLBreakdown()
        breakdown.scheme = components.scheme
        breakdown.user = components.user
        breakdown.host = components.host
        breakdown.port = components.port
        breakdown.path = components.path.isEmpty ? nil : components.path
        breakdown.fragment = components.fragment
        breakdown.queryItems = (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        return breakdown
    }

    private func breakdownPane(_ breakdown: URLBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "URL breakdown") {}
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                if let scheme = breakdown.scheme {
                    breakdownRow("Scheme", scheme)
                }
                if let user = breakdown.user {
                    breakdownRow("User", user)
                }
                if let host = breakdown.host {
                    breakdownRow("Host", host)
                }
                if let port = breakdown.port {
                    breakdownRow("Port", String(port))
                }
                if let path = breakdown.path {
                    breakdownRow("Path", path)
                }
                if let fragment = breakdown.fragment {
                    breakdownRow("Fragment", fragment)
                }
                ForEach(Array(breakdown.queryItems.enumerated()), id: \.offset) { _, item in
                    breakdownRow("Query: \(item.name)", item.value)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
    }

    private func breakdownRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    // MARK: - Transform

    private struct TransformResult {
        var text = ""
        var error: String? = nil
    }

    private var output: TransformResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return TransformResult() }
        return direction == .encode ? encode(trimmed) : decode(trimmed)
    }

    private func encode(_ input: String) -> TransformResult {
        if fullURLMode {
            return TransformResult(text: Self.encodeFullURL(input))
        }
        return TransformResult(text: Self.encodeComponent(input))
    }

    private func decode(_ input: String) -> TransformResult {
        var text = input
        if plusMeansSpace {
            text = text.replacingOccurrences(of: "+", with: " ")
        }

        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "%" {
                guard let first = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
                      let second = text.index(first, offsetBy: 1, limitedBy: text.endIndex),
                      second < text.endIndex,
                      let byte = UInt8(text[first...second], radix: 16)
                else {
                    let offset = text.distance(from: text.startIndex, to: index)
                    return TransformResult(error: "Invalid percent-encoding at offset \(offset)")
                }
                bytes.append(byte)
                index = text.index(after: second)
            } else {
                bytes.append(contentsOf: Array(String(char).utf8))
                index = text.index(after: index)
            }
        }

        guard let decoded = String(bytes: bytes, encoding: .utf8) else {
            return TransformResult(error: "Invalid UTF-8")
        }
        return TransformResult(text: decoded)
    }

    // MARK: - Encoding helpers

    /// RFC 3986 unreserved characters: everything else is percent-encoded.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Characters left alone in full-URL mode: unreserved plus reserved/gen-delims/sub-delims.
    private static let urlStructural = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=")

    private static func encodeComponent(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    /// Percent-encodes only characters outside the generous URL set, preserving structure.
    private static func encodeFullURL(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            if urlStructural.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    result += String(format: "%%%02X", byte)
                }
            }
        }
        return result
    }
}
