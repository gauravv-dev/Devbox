import SwiftUI
import Foundation

/// Base64 encoder/decoder with URL-safe alphabet and hex support, transforming live.
struct Base64ToolView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case encode = "Encode"
        case decode = "Decode"
        var id: String { rawValue }
    }

    private enum Encoding: String, CaseIterable, Identifiable {
        case text = "UTF-8 text"
        case hex = "Hex"
        var id: String { rawValue }
    }

    @State private var direction: Direction = .encode
    @State private var urlSafe = false
    @State private var encoding: Encoding = .text
    @State private var input = ""

    var body: some View {
        ToolContainer(title: "Base64",
                      subtitle: "Encode and decode Base64 with standard or URL-safe alphabets") {
            VStack(alignment: .leading, spacing: 12) {
                controls
                inputPane
                outputPane
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

            Toggle("URL-safe alphabet", isOn: $urlSafe)
                .toggleStyle(.checkbox)
                .help(direction == .encode
                      ? "Output uses - and _ with no padding; decoding accepts both alphabets either way"
                      : "Decoding accepts both standard and URL-safe alphabets")

            Picker(direction == .encode ? "Input is" : "Show result as", selection: $encoding) {
                ForEach(Encoding.allCases) { Text($0.rawValue).tag($0) }
            }

            Spacer()
        }
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: inputTitle, badge: inputBadge) {
                OpenFileButton(text: $input)
                ToolButton(title: "Clear", systemImage: "trash") { input = "" }
            }
            CodeEditor(text: $input, placeholder: inputPlaceholder)
                .frame(minHeight: 120)
        }
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: outputTitle, badge: result.byteCount.map { "\($0) bytes" }) {
                CopyButton(text: { result.output })
                SaveFileButton(text: { result.output },
                               filename: direction == .encode ? "encoded.txt" : "decoded.txt")
            }
            if let note = result.note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            CodeEditor(text: .constant(result.output), editable: false)
                .frame(minHeight: 120)
            if let error = result.error {
                StatusBadge(message: error, isError: true)
            }
        }
    }

    private var inputTitle: String {
        direction == .encode
            ? (encoding == .hex ? "Input (hex)" : "Input (text)")
            : "Input (base64)"
    }

    private var outputTitle: String {
        direction == .encode ? "Output (base64)" : "Output"
    }

    private var inputBadge: String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return direction == .encode ? "\(trimmed.count) chars" : nil
    }

    private var inputPlaceholder: String {
        switch direction {
        case .encode: return encoding == .hex ? "48 65 6c 6c 6f…" : "Type or paste text to encode…"
        case .decode: return "Paste base64 (standard or URL-safe)…"
        }
    }

    // MARK: - Transform

    private struct TransformResult {
        var output = ""
        var note: String? = nil
        var error: String? = nil
        var byteCount: Int? = nil
    }

    private var result: TransformResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return TransformResult() }
        return direction == .encode ? encode(trimmed) : decode(trimmed)
    }

    private func encode(_ input: String) -> TransformResult {
        var result = TransformResult()
        let bytes: Data
        if encoding == .hex {
            switch Self.hexToBytes(input) {
            case .success(let data): bytes = data
            case .failure(let err):
                result.error = err.message
                return result
            }
        } else {
            bytes = Data(input.utf8)
        }
        var encoded = bytes.base64EncodedString()
        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        result.output = encoded
        result.byteCount = bytes.count
        return result
    }

    private func decode(_ input: String) -> TransformResult {
        var result = TransformResult()
        // Tolerate pasted base64 wrapped across lines.
        var normalized = input.replacingOccurrences(of: "[\\s]+", with: "", options: .regularExpression)
        // Accept both alphabets regardless of the toggle.
        normalized = normalized
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        if let bad = normalized.unicodeScalars.first(where: { !Self.base64Characters.contains($0) }) {
            result.error = "Invalid base64: unexpected character '\(bad)'"
            return result
        }
        let stripped = normalized.replacingOccurrences(of: "=", with: "")
        switch stripped.count % 4 {
        case 1:
            result.error = "Invalid base64: length"
            return result
        case 2: normalized = stripped + "=="
        case 3: normalized = stripped + "="
        default: normalized = stripped
        }
        guard let bytes = Data(base64Encoded: normalized) else {
            result.error = "Invalid base64: length/characters"
            return result
        }
        result.byteCount = bytes.count
        if encoding == .hex {
            result.output = Self.bytesToHex(bytes)
            result.note = "Showing hex (\(bytes.count) bytes)"
        } else if let text = String(data: bytes, encoding: .utf8) {
            result.output = text
        } else {
            result.output = Self.bytesToHex(bytes)
            result.note = "(not valid UTF-8 — showing hex)"
        }
        return result
    }

    // MARK: - Helpers

    private static let base64Characters = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")

    private struct HexParseError: Error {
        let message: String
    }

    private static func hexToBytes(_ input: String) -> Result<Data, HexParseError> {
        let cleaned = input.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return .success(Data()) }
        guard cleaned.count % 2 == 0 else {
            return .failure(HexParseError(message: "Invalid hex: odd number of digits"))
        }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                return .failure(HexParseError(message: "Invalid hex: unexpected character near offset \(cleaned.distance(from: cleaned.startIndex, to: index))"))
            }
            data.append(byte)
            index = next
        }
        return .success(data)
    }

    private static func bytesToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
