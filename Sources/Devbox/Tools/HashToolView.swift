import AppKit
import CryptoKit
import Foundation
import SwiftUI

/// Text hashing (MD5, SHA-1, SHA-256/384/512) plus HMAC with selectable algorithms.
struct HashToolView: View {
    private enum HashAlgorithm: String, CaseIterable, Identifiable {
        case md5 = "MD5"
        case sha1 = "SHA-1"
        case sha256 = "SHA-256"
        case sha384 = "SHA-384"
        case sha512 = "SHA-512"

        var id: String { rawValue }

        func digest(of data: Data) -> Data? {
            switch self {
            case .md5:
                return Data(LegacyDigest.md5(of: Array(data)))
            case .sha1:
                return Data(LegacyDigest.sha1(of: Array(data)))
            case .sha256:
                return Data(SHA256.hash(data: data))
            case .sha384:
                return Data(SHA384.hash(data: data))
            case .sha512:
                return Data(SHA512.hash(data: data))
            }
        }
    }

    private enum HmacAlgorithm: String, CaseIterable, Identifiable {
        case sha256 = "SHA-256"
        case sha384 = "SHA-384"
        case sha512 = "SHA-512"

        var id: String { rawValue }
    }

    @State private var input = ""
    @State private var inputIsHex = false
    @State private var uppercaseHex = false
    @State private var hmacKey = ""
    @State private var keyIsHex = false
    @State private var hmacAlgorithm: HmacAlgorithm = .sha256

    var body: some View {
        ToolContainer(title: "Hash", subtitle: "Text hashing with MD5, SHA-1, SHA-2 family and HMAC") {
            HSplitView {
                inputPane
                    .frame(minWidth: 320, maxWidth: .infinity)
                outputPane
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        }
    }

    // MARK: - Input pane

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Input", badge: inputIsHex ? "hex" : "\(input.utf8.count) bytes") {
                OpenFileButton(text: $input)
            }
            CodeEditor(text: $input, placeholder: "Type or paste text, or open a file…", editable: true)
                .frame(minWidth: 320, minHeight: 180)
                .frame(maxWidth: .infinity, minHeight: 220)
            Toggle("Treat input as hex bytes", isOn: $inputIsHex)
            if let error = inputDataError {
                StatusBadge(message: error, isError: true)
            }
        }
    }

    // MARK: - Output pane

    private var outputPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Uppercase hex output", isOn: $uppercaseHex)
                if inputData == nil {
                    StatusBadge(message: inputDataError ?? "Enter input to see digests.", isError: inputDataError != nil)
                } else {
                    ForEach(HashAlgorithm.allCases) { algorithm in
                        if let digest = algorithm.digest(of: inputData!) {
                            digestRow(algorithm.rawValue, hex(digest))
                        }
                    }
                }
                Divider()
                hmacSection
            }
            .padding(.vertical, 4)
        }
    }

    private func digestRow(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                CopyButton(text: { value })
            }
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var hmacSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "HMAC") { EmptyView() }
            HStack(spacing: 8) {
                TextField("Key", text: $hmacKey, prompt: Text("Secret key"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Toggle("Key is hex", isOn: $keyIsHex)
                Picker("Algorithm", selection: $hmacAlgorithm) {
                    ForEach(HmacAlgorithm.allCases) { algorithm in
                        Text(algorithm.rawValue).tag(algorithm)
                    }
                }
                .frame(maxWidth: 160)
            }
            if let keyError = hmacKeyError {
                StatusBadge(message: keyError, isError: true)
            } else if let output = hmacOutput {
                digestRow("HMAC-\(hmacAlgorithm.rawValue)", output)
            }
        }
    }

    // MARK: - Logic

    /// Decoded input data; nil when there is nothing to hash.
    private var inputData: Data? {
        if inputIsHex {
            return Self.data(fromHex: input)
        }
        return input.isEmpty ? nil : Data(input.utf8)
    }

    private var inputDataError: String? {
        guard inputIsHex else { return nil }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Self.data(fromHex: input) == nil
            ? "Invalid hex input — use an even number of hex characters (0-9, a-f)."
            : nil
    }

    private var hmacKeyData: Data? {
        guard !hmacKey.isEmpty else { return nil }
        if keyIsHex {
            return Self.data(fromHex: hmacKey)
        }
        return Data(hmacKey.utf8)
    }

    private var hmacKeyError: String? {
        guard keyIsHex, !hmacKey.isEmpty else { return nil }
        return Self.data(fromHex: hmacKey) == nil
            ? "Invalid hex key — use an even number of hex characters."
            : nil
    }

    private var hmacOutput: String? {
        guard let data = inputData, let key = hmacKeyData else { return nil }
        let keyData = SymmetricKey(data: key)
        let digest: Data
        switch hmacAlgorithm {
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(for: data, using: keyData))
        case .sha384:
            digest = Data(HMAC<SHA384>.authenticationCode(for: data, using: keyData))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(for: data, using: keyData))
        }
        return hex(digest)
    }

    private func hex(_ data: Data) -> String {
        let string = data.map { String(format: "%02x", $0) }.joined()
        return uppercaseHex ? string.uppercased() : string
    }

    /// Decodes a hex string (whitespace-tolerant, case-insensitive) into Data; nil on invalid input.
    private static func data(fromHex string: String) -> Data? {
        let characters = string.filter { !$0.isWhitespace }
        guard !characters.isEmpty, characters.count % 2 == 0 else { return nil }
        var data = Data(capacity: characters.count / 2)
        var index = characters.startIndex
        while index < characters.endIndex {
            let next = characters.index(index, offsetBy: 2)
            guard let byte = UInt8(characters[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
