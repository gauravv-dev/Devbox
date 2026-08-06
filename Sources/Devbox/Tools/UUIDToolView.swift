import Foundation
import SwiftUI

/// UUID generator: v4 (random) and v5 (name-based, SHA-1 per RFC 4122).
struct UUIDToolView: View {
    private enum Version: String, CaseIterable, Identifiable {
        case v4 = "v4 (random)"
        case v5 = "v5 (named)"

        var id: String { rawValue }
    }

    private enum NamespaceKind: String, CaseIterable, Identifiable {
        case dns = "DNS"
        case url = "URL"
        case oid = "OID"
        case x500 = "X.500"
        case custom = "Custom"

        var id: String { rawValue }

        /// The RFC 4122 predefined namespace UUIDs as raw 16-byte values.
        var uuidBytes: [UInt8]? {
            switch self {
            case .dns:
                return [0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
                        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
            case .url:
                return [0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
                        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
            case .oid:
                return [0x6b, 0xa7, 0xb8, 0x12, 0x9d, 0xad, 0x11, 0xd1,
                        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
            case .x500:
                return [0x6b, 0xa7, 0xb8, 0x14, 0x9d, 0xad, 0x11, 0xd1,
                        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
            case .custom:
                return nil
            }
        }
    }

    @State private var count = 5
    @State private var uppercase = true
    @State private var includeHyphens = true
    @State private var version: Version = .v4
    @State private var namespaceKind: NamespaceKind = .dns
    @State private var customSeed = ""
    @State private var v5Name = ""
    @State private var quick = UUID().uuidString
    @State private var results = ""
    @State private var resultCount = 0

    var body: some View {
        ToolContainer(title: "UUID", subtitle: "Generate RFC 4122 UUIDs — v4 random, v5 name-based (SHA-1)") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quickSection
                    Divider()
                    controlsSection
                    Divider()
                    resultsSection
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Sections

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick UUID").font(.headline)
            HStack(spacing: 8) {
                Text(quick)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                CopyButton(text: { quick })
                ToolButton(title: "Regenerate", systemImage: "arrow.clockwise") {
                    quick = generateOne() ?? UUID().uuidString
                }
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Stepper(value: $count, in: 1...100) {
                    TextField("Count", value: $count, format: .number)
                        .frame(width: 52)
                }
                .onChange(of: count) { _, newValue in
                    count = min(max(newValue, 1), 100)
                }

                Toggle("Uppercase", isOn: $uppercase)
                Toggle("Include hyphens", isOn: $includeHyphens)

                Picker("Version", selection: $version) {
                    ForEach(Version.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            if version == .v5 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Picker("Namespace", selection: $namespaceKind) {
                            ForEach(NamespaceKind.allCases) { ns in
                                Text(ns.rawValue).tag(ns)
                            }
                        }
                        .frame(maxWidth: 220)

                        TextField("Name", text: $v5Name, prompt: Text("Name to hash"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                    }
                    if namespaceKind == .custom {
                        TextField("Custom namespace seed", text: $customSeed,
                                  prompt: Text("Seed string for custom namespace"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 420)
                        Text("Custom namespace = first 16 bytes of SHA-1(seed).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("v5 = SHA-1(namespace UUID bytes + name UTF-8) per RFC 4122; version nibble set to 5, variant bits 10xx. Deterministic: the same namespace + name always yields the same UUID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let problem = validationProblem {
                        StatusBadge(message: problem, isError: true)
                    }
                }
            }

            HStack(spacing: 8) {
                ToolButton(title: "Generate", systemImage: "sparkles") {
                    generate()
                }
                .disabled(!canGenerate)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Results",
                       badge: resultCount > 0 ? "\(resultCount) UUID\(resultCount == 1 ? "" : "s")" : nil) {
                CopyButton(text: { results }, label: "Copy all")
                SaveFileButton(text: { results }, filename: "uuids.txt")
            }
            CodeEditor(text: $results,
                       placeholder: "Generated UUIDs appear here, one per line.",
                       editable: false)
                .frame(minWidth: 420, minHeight: 180)
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    // MARK: - Logic

    private var validationProblem: String? {
        guard version == .v5 else { return nil }
        if v5Name.isEmpty { return "Enter a name to hash for v5." }
        if namespaceKind == .custom && customSeed.isEmpty { return "Enter a seed for the custom namespace." }
        return nil
    }

    private var canGenerate: Bool { validationProblem == nil }

    private func generate() {
        guard canGenerate else { return }
        let lines = (0..<count).compactMap { _ in generateOne() }
        results = lines.joined(separator: "\n")
        resultCount = lines.count
    }

    /// Generates a single UUID string honoring the current version/namespace settings,
    /// before case/hyphen formatting.
    private func generateOneRaw() -> String? {
        switch version {
        case .v4:
            return UUID().uuidString
        case .v5:
            guard !v5Name.isEmpty, let namespaceBytes = currentNamespaceBytes else { return nil }
            return Self.uuidv5(namespace: namespaceBytes, name: v5Name)
        }
    }

    private func generateOne() -> String? {
        generateOneRaw().map(format)
    }

    private var currentNamespaceBytes: [UInt8]? {
        if let predefined = namespaceKind.uuidBytes { return predefined }
        // Custom: SHA-1(seed) truncated to 16 bytes.
        return Array(UUIDSHA1.digest(of: Array(customSeed.utf8)).prefix(16))
    }

    private func format(_ uuid: String) -> String {
        var result = includeHyphens ? uuid : uuid.replacingOccurrences(of: "-", with: "")
        result = uppercase ? result.uppercased() : result.lowercased()
        return result
    }

    /// RFC 4122 version 5 UUID: SHA-1(namespace 16 bytes + name UTF-8),
    /// version nibble forced to 5 and variant bits forced to 10xx.
    private static func uuidv5(namespace: [UInt8], name: String) -> String {
        var digest = UUIDSHA1.digest(of: namespace + Array(name.utf8))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        let hex = digest.map { String(format: "%02x", $0) }
        return "\(hex[0..<4].joined())-\(hex[4..<6].joined())-\(hex[6..<8].joined())-\(hex[8..<10].joined())-\(hex[10..<16].joined())"
    }
}

/// Standard SHA-1 (FIPS 180-1). CryptoKit does not ship SHA-1;
/// v5 UUIDs require it, so a minimal private implementation lives here.
private enum UUIDSHA1 {
    static func digest(of input: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var message = input
        let bitLength = UInt64(input.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var w = [UInt32](repeating: 0, count: 80)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(message[j]) << 24)
                    | (UInt32(message[j + 1]) << 16)
                    | (UInt32(message[j + 2]) << 8)
                    | UInt32(message[j + 3])
            }
            for i in 16..<80 {
                let mixed = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (mixed << 1) | (mixed >> 31)
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            for i in 0..<80 {
                let f: UInt32
                let roundK: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    roundK = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    roundK = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    roundK = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    roundK = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ roundK &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h0 &+= a
            h1 &+= b
            h2 &+= c
            h3 &+= d
            h4 &+= e
        }

        var output = [UInt8]()
        output.reserveCapacity(20)
        for word in [h0, h1, h2, h3, h4] {
            output.append(UInt8(truncatingIfNeeded: word >> 24))
            output.append(UInt8(truncatingIfNeeded: word >> 16))
            output.append(UInt8(truncatingIfNeeded: word >> 8))
            output.append(UInt8(truncatingIfNeeded: word))
        }
        return output
    }
}
