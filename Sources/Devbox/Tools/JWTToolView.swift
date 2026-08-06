import SwiftUI
import Foundation
import CryptoKit

/// Decodes JSON Web Tokens (structure and claims only — no signature verification)
/// and shows the header, payload, signature bytes, and time-claim status live.
struct JWTToolView: View {
    @State private var token = ""

    var body: some View {
        ToolContainer(title: "JWT Decoder",
                      subtitle: "Decode JSON Web Tokens and inspect header, claims, signature, and expiry") {
            VStack(alignment: .leading, spacing: 12) {
                inputPane
                if let parsed = Self.parse(token) {
                    StatusBadge(message: statusMessage(for: parsed), isError: parsed.error != nil)
                    if parsed.error == nil {
                        segmentPanes(parsed)
                        signaturePane(parsed)
                        if !parsed.claims.isEmpty {
                            claimsPane(parsed)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Panes

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Token") {
                OpenFileButton(text: $token)
                ToolButton(title: "Sample", systemImage: "wand.and.stars") {
                    token = Self.makeSampleToken()
                }
                ToolButton(title: "Clear", systemImage: "trash") {
                    token = ""
                }
            }
            CodeEditor(text: $token, placeholder: "Paste JWT (eyJhbGc…)")
                .frame(minHeight: 96, maxHeight: 160)
        }
    }

    private func segmentPanes(_ parsed: ParsedJWT) -> some View {
        HSplitView {
            jsonPane(title: "Header", json: parsed.headerJSON, filename: "header.json")
            jsonPane(title: "Payload (claims)", json: parsed.payloadJSON, filename: "payload.json")
        }
        .frame(minHeight: 200, maxHeight: .infinity)
    }

    private func jsonPane(title: String, json: String, filename: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: title) {
                CopyButton(text: { json })
                SaveFileButton(text: { json }, filename: filename)
            }
            CodeEditor(text: .constant(json), editable: false)
        }
        .frame(minWidth: 260, maxWidth: .infinity)
    }

    private func signaturePane(_ parsed: ParsedJWT) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Signature", badge: parsed.alg) {
                if let signature = parsed.signatureB64URL {
                    CopyButton(text: { signature })
                }
            }
            if let signature = parsed.signatureB64URL {
                Text(signature)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                if let hex = parsed.signatureHexPreview {
                    Text("Hex: \(hex)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("Unsigned token — no signature segment present.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let note = Self.algNote(for: parsed.alg) {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
    }

    private func claimsPane(_ parsed: ParsedJWT) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Time claims (iat / nbf / exp)") {}
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    Text("Claim").bold()
                    Text("Epoch").bold()
                    Text("UTC").bold()
                    Text("Local").bold()
                    Text("Relative").bold()
                }
                ForEach(parsed.claims) { claim in
                    GridRow {
                        Text(claim.name)
                        Text(claim.epoch)
                        Text(claim.utc)
                        Text(claim.local)
                        Text(claim.relative)
                    }
                    .font(.system(.callout, design: .monospaced))
                }
            }
            if let exp = parsed.expDate {
                expiryBadge(for: exp)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
    }

    @ViewBuilder
    private func expiryBadge(for exp: Date) -> some View {
        let relative = Self.relativeDescription(to: exp)
        if exp <= Date() {
            StatusBadge(message: "Token EXPIRED \(relative)", isError: true)
        } else {
            StatusBadge(message: "Expires \(Self.utcFormatter.string(from: exp)) (\(relative))", isError: false)
        }
    }

    private func statusMessage(for parsed: ParsedJWT) -> String {
        if let error = parsed.error { return error }
        return parsed.segmentCount == 2
            ? "Valid JWT structure — 2 segments (unsigned)"
            : "Valid JWT structure — 3 segments"
    }

    // MARK: - Parse model

    private struct ParsedJWT {
        var error: String? = nil
        var segmentCount = 0
        var headerJSON = ""
        var payloadJSON = ""
        var alg: String? = nil
        var signatureB64URL: String? = nil
        var signatureHexPreview: String? = nil
        var claims: [Claim] = []
        var expDate: Date? = nil
    }

    private struct Claim: Identifiable {
        let name: String
        let epoch: String
        let utc: String
        let local: String
        let relative: String
        var id: String { name }
    }

    private static func parse(_ raw: String) -> ParsedJWT? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        var result = ParsedJWT()
        let segments = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count == 2 || segments.count == 3 else {
            result.error = "Not a JWT: expected 2 or 3 dot-separated segments, got \(segments.count)"
            return result
        }
        if segments.count == 3 && segments[2].isEmpty {
            result.error = "Not a JWT: signature segment is empty"
            return result
        }
        result.segmentCount = segments.count

        guard let headerData = base64URLDecode(segments[0]) else {
            result.error = "Header is not valid base64url"
            return result
        }
        guard let payloadData = base64URLDecode(segments[1]) else {
            result.error = "Payload is not valid base64url"
            return result
        }
        guard let headerObject = try? JSONSerialization.jsonObject(with: headerData) else {
            result.error = "Header is not valid JSON"
            return result
        }
        guard let payloadObject = try? JSONSerialization.jsonObject(with: payloadData) else {
            result.error = "Payload is not valid JSON"
            return result
        }

        result.headerJSON = prettyJSON(headerObject)
        result.payloadJSON = prettyJSON(payloadObject)
        result.alg = (headerObject as? [String: Any])?["alg"] as? String

        if segments.count == 3 {
            result.signatureB64URL = segments[2]
            guard let signatureData = base64URLDecode(segments[2]) else {
                result.error = "Signature is not valid base64url"
                return result
            }
            let hex = hexString(signatureData)
            result.signatureHexPreview = hex.count > 64 ? String(hex.prefix(64)) + "…" : hex
        }

        if let payloadDict = payloadObject as? [String: Any] {
            for name in ["iat", "nbf", "exp"] {
                guard let number = payloadDict[name] as? NSNumber else { continue }
                let date = Date(timeIntervalSince1970: number.doubleValue)
                result.claims.append(Claim(
                    name: name,
                    epoch: epochString(number.doubleValue),
                    utc: utcFormatter.string(from: date),
                    local: localFormatter.string(from: date),
                    relative: relativeDescription(to: date)))
            }
            if let exp = payloadDict["exp"] as? NSNumber {
                result.expDate = Date(timeIntervalSince1970: exp.doubleValue)
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func base64URLDecode(_ segment: String) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch base64.count % 4 {
        case 1: return nil
        case 2: base64 += "=="
        case 3: base64 += "="
        default: break
        }
        return Data(base64Encoded: base64)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func prettyJSON(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                    options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    private static func epochString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 9_000_000_000_000_000_000 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func algNote(for alg: String?) -> String? {
        guard let alg, !alg.isEmpty else { return nil }
        if ["HS256", "HS384", "HS512"].contains(alg) {
            return "\(alg): HMAC — verification requires secret (not supported offline)"
        }
        if alg.hasPrefix("RS") || alg.hasPrefix("ES") || alg.hasPrefix("PS") {
            return "\(alg): Asymmetric — verify with issuer public key"
        }
        return "\(alg): unknown algorithm — signature not interpreted"
    }

    private static func relativeDescription(to date: Date, from now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        let seconds = Int(interval.magnitude)
        let units: [(Int, String)] = [
            (31_536_000, "year"), (2_592_000, "month"), (86_400, "day"),
            (3_600, "hour"), (60, "minute"), (1, "second"),
        ]
        for (unitSeconds, unitName) in units where seconds >= unitSeconds {
            let value = seconds / unitSeconds
            let name = value == 1 ? unitName : unitName + "s"
            return interval >= 0 ? "in \(value) \(name)" : "\(value) \(name) ago"
        }
        return interval >= 0 ? "in a few seconds" : "a few seconds ago"
    }

    /// Builds a realistic-looking HS256 sample token (header, claims, and a real HMAC signature).
    private static func makeSampleToken() -> String {
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let payload: [String: Any] = [
            "sub": "1234567890",
            "name": "Jane Doe",
            "iat": 1_516_239_022,
            "exp": Int(Date().timeIntervalSince1970) + 86_400,
        ]
        guard let headerData = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return "" }
        let signingInput = base64URLEncode(headerData) + "." + base64URLEncode(payloadData)
        let key = SymmetricKey(data: Data("devbox-sample-secret".utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        return signingInput + "." + base64URLEncode(Data(code))
    }

    // MARK: - Formatters

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        formatter.timeZone = .current
        return formatter
    }()
}
