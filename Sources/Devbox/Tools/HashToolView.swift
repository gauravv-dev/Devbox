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
                return Data(HashMD5.digest(of: Array(data)))
            case .sha1:
                return Data(HashSHA1.digest(of: Array(data)))
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

// MARK: - MD5 (RFC 1321)

/// Standard MD5. CryptoKit does not ship MD5, so a compact private implementation lives here.
private enum HashMD5 {
    private static let k: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]

    private static let shift: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    static func digest(of input: [UInt8]) -> [UInt8] {
        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        var message = input
        let bitLength = UInt64(input.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for i in 0..<8 {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(8 * i)))
        }

        var m = [UInt32](repeating: 0, count: 16)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                m[i] = UInt32(message[j])
                    | (UInt32(message[j + 1]) << 8)
                    | (UInt32(message[j + 2]) << 16)
                    | (UInt32(message[j + 3]) << 24)
            }

            var a = a0
            var b = b0
            var c = c0
            var d = d0
            for i in 0..<64 {
                var f: UInt32
                var g: Int
                switch i {
                case 0..<16:
                    f = (b & c) | (~b & d)
                    g = i
                case 16..<32:
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ m[g]
                a = d
                d = c
                c = b
                b = b &+ ((f << shift[i]) | (f >> (32 - shift[i])))
            }
            a0 &+= a
            b0 &+= b
            c0 &+= c
            d0 &+= d
        }

        var output = [UInt8]()
        output.reserveCapacity(16)
        for word in [a0, b0, c0, d0] {
            for i in 0..<4 {
                output.append(UInt8(truncatingIfNeeded: word >> UInt32(8 * i)))
            }
        }
        return output
    }
}

// MARK: - SHA-1 (FIPS 180-1)

/// Standard SHA-1. CryptoKit does not ship SHA-1, so a private implementation lives here.
private enum HashSHA1 {
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
