import Foundation

/// RFC 4122 UUID toolkit: parse/validate/inspect, name-based generation (v3/v5),
/// and canonical-format conversions.
enum UUIDKit {

    // MARK: - Namespaces (RFC 4122 Appendix C)

    enum Namespace: String, CaseIterable, Identifiable {
        case dns = "DNS"
        case url = "URL"
        case oid = "OID"
        case x500 = "X.500"
        case custom = "Custom"

        var id: String { rawValue }

        var bytes: [UInt8]? {
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

    static func namespaceBytes(_ ns: Namespace, customSeed: String) -> [UInt8]? {
        if let predefined = ns.bytes { return predefined }
        guard !customSeed.isEmpty else { return nil }
        return Array(LegacyDigest.sha1(of: Array(customSeed.utf8)).prefix(16))
    }

    // MARK: - Parsing / validation

    struct Info {
        let normalized: String     // canonical hyphenated lowercase hex
        let hexDigits: String      // 32 lowercase hex digits, no hyphens
        let version: Int
        let variantName: String
        let isNil: Bool
        let isMax: Bool
        let timestamp: Date?       // v1/v6 (100ns ticks since 1582) or v7 (unix ms)
        let clockSeq: Int?         // v1/v6
        let nodeMAC: String?       // v1/v6
        let multicastBit: Bool?    // v1/v6
    }

    struct ParseError: Error {
        let message: String
    }

    static func parse(_ raw: String) -> Result<Info, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(ParseError(message: "Input is empty")) }

        var s = trimmed
        if s.lowercased().hasPrefix("urn:uuid:") {
            s = String(s.dropFirst("urn:uuid:".count))
        } else if s.hasPrefix("{") && s.hasSuffix("}") && s.count == 38 {
            s = String(s.dropFirst().dropLast())
        }

        let hyphens = s.contains("-")
        let hexOnly = s.replacingOccurrences(of: "-", with: "")
        guard hexOnly.count == 32 else {
            let hint: String
            if s.count == 36 && !hyphens {
                hint = "36 characters but no hyphens — expected the 8-4-4-4-12 shape"
            } else {
                hint = "expected 32 hex digits, got \(hexOnly.count)"
            }
            return .failure(ParseError(message: hint))
        }
        guard hexOnly.allSatisfy({ $0.isHexDigit }) else {
            return .failure(ParseError(message: "contains non-hex characters"))
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        var idx = hexOnly.startIndex
        while idx < hexOnly.endIndex {
            let next = hexOnly.index(idx, offsetBy: 2)
            guard let byte = UInt8(hexOnly[idx..<next], radix: 16) else {
                return .failure(ParseError(message: "invalid byte encoding"))
            }
            bytes.append(byte)
            idx = next
        }

        let version = Int(bytes[6] >> 4)
        let variantByte = bytes[8]
        let variantName: String
        if variantByte & 0x80 == 0x00 {
            variantName = "NCS backward compatibility (0xxx)"
        } else if variantByte & 0xC0 == 0x80 {
            variantName = "RFC 4122 (10xx)"
        } else if variantByte & 0xE0 == 0xC0 {
            variantName = "Microsoft Corporation (110x)"
        } else {
            variantName = "Reserved (111x)"
        }

        var timestamp: Date?
        var clockSeq: Int?
        var nodeMAC: String?
        var multicast: Bool?
        if version == 1 || version == 6 {
            // 60-bit timestamp: time_hi|time_mid|time_low reassembled big-endian.
            let ticks = (UInt64(bytes[6] & 0x0F) << 56) | (UInt64(bytes[7]) << 48)
                | (UInt64(bytes[4]) << 40) | (UInt64(bytes[5]) << 32)
                | (UInt64(bytes[0]) << 24) | (UInt64(bytes[1]) << 16)
                | (UInt64(bytes[2]) << 8) | UInt64(bytes[3])
            // Ticks since 1582-10-15; unix epoch starts 122192928000000000 ticks later.
            let unixTicks = Int64(bitPattern: ticks &- 122_192_928_000_000_000)
            timestamp = Date(timeIntervalSince1970: TimeInterval(unixTicks) / 10_000_000)
            clockSeq = (Int(bytes[8] & 0x3F) << 8) | Int(bytes[9])
            nodeMAC = bytes[10...].map { String(format: "%02x", $0) }.joined(separator: ":")
            multicast = bytes[10] & 0x01 == 0x01
        } else if version == 7 {
            let ms = (UInt64(bytes[0]) << 40) | (UInt64(bytes[1]) << 32)
                | (UInt64(bytes[2]) << 24) | (UInt64(bytes[3]) << 16)
                | (UInt64(bytes[4]) << 8) | UInt64(bytes[5])
            timestamp = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        }

        let hexLower = hexOnly.lowercased()
        let canonical = "\(hexLower.prefix(8))-\(hexLower.dropFirst(8).prefix(4))-\(hexLower.dropFirst(12).prefix(4))-\(hexLower.dropFirst(16).prefix(4))-\(hexLower.dropFirst(20))"
        return .success(Info(
            normalized: canonical,
            hexDigits: hexLower,
            version: version,
            variantName: variantName,
            isNil: bytes.allSatisfy { $0 == 0 },
            isMax: bytes.allSatisfy { $0 == 0xFF },
            timestamp: timestamp,
            clockSeq: clockSeq,
            nodeMAC: nodeMAC,
            multicastBit: multicast
        ))
    }

    static func versionName(_ version: Int) -> String {
        switch version {
        case 0: return "0 · NCS backward compatibility"
        case 1: return "1 · time-based"
        case 2: return "2 · DCE security"
        case 3: return "3 · name-based (MD5)"
        case 4: return "4 · random"
        case 5: return "5 · name-based (SHA-1)"
        case 6: return "6 · reordered time"
        case 7: return "7 · Unix epoch time"
        case 8: return "8 · custom / vendor"
        default: return "\(version) · unknown"
        }
    }

    // MARK: - Name-based generation (RFC 4122 §4.3)

    /// Deterministic UUID: v3 hashes namespace+name with MD5, v5 with SHA-1.
    static func named(version: Int, namespace: [UInt8], name: String) -> String {
        precondition(version == 3 || version == 5)
        var digest = version == 3
            ? LegacyDigest.md5(of: namespace + Array(name.utf8))
            : LegacyDigest.sha1(of: namespace + Array(name.utf8))
        digest[6] = (digest[6] & 0x0F) | (UInt8(version) << 4)
        digest[8] = (digest[8] & 0x3F) | 0x80
        return hyphenate(digest)
    }

    private static func hyphenate(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }
        return "\(hex[0..<4].joined())-\(hex[4..<6].joined())-\(hex[6..<8].joined())-\(hex[8..<10].joined())-\(hex[10..<16].joined())"
    }

    // MARK: - Formatting

    enum Format: String, CaseIterable, Identifiable {
        case canonical = "Canonical"
        case plain = "Plain (no hyphens)"
        case braced = "Braced {…}"
        case urn = "URN (urn:uuid:)"
        case quoted = "Quoted \"…\""
        case javaArray = "Java byte[]"
        case cArray = "C byte array"

        var id: String { rawValue }

        func render(canonical: String, uppercase: Bool) -> String {
            let base = uppercase ? canonical.uppercased() : canonical.lowercased()
            let hexOnly = base.replacingOccurrences(of: "-", with: "")
            switch self {
            case .canonical:
                return base
            case .plain:
                return hexOnly
            case .braced:
                return "{\(base)}"
            case .urn:
                return "urn:uuid:\(base.lowercased())"
            case .quoted:
                return "\"\(base)\""
            case .javaArray:
                let signed = stride(from: 0, to: 32, by: 2).compactMap { i -> Int? in
                    guard let byte = UInt8(hexOnly.dropFirst(i).prefix(2), radix: 16) else { return nil }
                    return byte >= 128 ? Int(byte) - 256 : Int(byte)
                }
                return "new byte[] { \(signed.map(String.init).joined(separator: ", ")) }"
            case .cArray:
                let hexBytes = stride(from: 0, to: 32, by: 2).compactMap { i -> String? in
                    UInt8(hexOnly.dropFirst(i).prefix(2), radix: 16).map { String(format: "0x%02x", $0) }
                }
                return "{ \(hexBytes.joined(separator: ", ")) }"
            }
        }
    }
}
