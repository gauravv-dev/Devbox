import Foundation
import SwiftUI

/// UUID suite: generate (v4 random, v5 named), convert string → deterministic UUID (v3/v5),
/// validate + inspect, and convert between canonical formats.
struct UUIDToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case generate = "Generate"
        case convert = "String → UUID"
        case validate = "Validate"
        case format = "Format"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .generate

    // Generate
    @State private var count = 5
    @State private var uppercase = true
    @State private var includeHyphens = true
    @State private var genVersion: GenVersion = .v4
    @State private var genNamespace: UUIDKit.Namespace = .dns
    @State private var genCustomSeed = ""
    @State private var genName = ""
    @State private var quick = UUID().uuidString
    @State private var results = ""
    @State private var resultCount = 0

    // Convert
    @State private var convertNamespace: UUIDKit.Namespace = .dns
    @State private var convertCustomSeed = ""
    @State private var convertVersion: ConvertVersion = .v5
    @State private var convertInput = ""
    @State private var convertResult = ""
    @State private var convertError: String?

    // Validate
    @State private var validateInput = ""

    // Format
    @State private var formatInput = ""
    @State private var formatUppercase = false
    @State private var formatResult: UUIDKit.Info?
    @State private var formatError: String?

    private enum GenVersion: String, CaseIterable, Identifiable {
        case v4 = "v4 (random)"
        case v5 = "v5 (named)"
        var id: String { rawValue }
    }

    private enum ConvertVersion: String, CaseIterable, Identifiable {
        case v5 = "v5 (SHA-1)"
        case v3 = "v3 (MD5)"
        var id: String { rawValue }
    }

    var body: some View {
        ToolContainer(title: "UUID", subtitle: "Generate, validate, convert, and format RFC 4122 UUIDs") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch mode {
                        case .generate: generateSection
                        case .convert: convertSection
                        case .validate: validateSection
                        case .format: formatSection
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Generate

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Divider()

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
                    Picker("Version", selection: $genVersion) {
                        ForEach(GenVersion.allCases) { v in Text(v.rawValue).tag(v) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                if genVersion == .v5 {
                    namedInputs(namespace: $genNamespace, seed: $genCustomSeed, name: $genName,
                                seedHint: "Custom namespace = first 16 bytes of SHA-1(seed).",
                                note: "Deterministic: same namespace + name always yields the same UUID.")
                }

                ToolButton(title: "Generate", systemImage: "sparkles") { generate() }
                    .disabled(!canGenerate)
            }

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
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    private var canGenerate: Bool {
        guard genVersion == .v5 else { return true }
        return !genName.isEmpty && (genNamespace != .custom || !genCustomSeed.isEmpty)
    }

    private func generate() {
        guard canGenerate else { return }
        let lines = (0..<count).compactMap { _ in generateOne() }
        results = lines.joined(separator: "\n")
        resultCount = lines.count
    }

    private func generateOne() -> String? {
        let raw: String?
        switch genVersion {
        case .v4:
            raw = UUID().uuidString
        case .v5:
            guard let ns = UUIDKit.namespaceBytes(genNamespace, customSeed: genCustomSeed),
                  !genName.isEmpty else { return nil }
            raw = UUIDKit.named(version: 5, namespace: ns, name: genName)
        }
        return raw.map(formatOutput)
    }

    private func formatOutput(_ uuid: String) -> String {
        var result = includeHyphens ? uuid : uuid.replacingOccurrences(of: "-", with: "")
        result = uppercase ? result.uppercased() : result.lowercased()
        return result
    }

    // MARK: - String → UUID

    private var convertSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Deterministically derive a UUID from any string — same input, same UUID.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                PaneHeader(title: "Input string") {
                    CopyButton(text: { convertInput }, label: "Copy")
                }
                CodeEditor(text: Binding(
                    get: { convertInput },
                    set: { convertInput = $0; recomputeConvert() }
                ), placeholder: "Any text — user ID, file path, name…")
                    .frame(minHeight: 90)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Picker("Namespace", selection: $convertNamespace) {
                        ForEach(UUIDKit.Namespace.allCases) { ns in Text(ns.rawValue).tag(ns) }
                    }
                    .frame(maxWidth: 220)
                    .onChange(of: convertNamespace) { _, _ in recomputeConvert() }

                    Picker("Hash", selection: $convertVersion) {
                        ForEach(ConvertVersion.allCases) { v in Text(v.rawValue).tag(v) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .onChange(of: convertVersion) { _, _ in recomputeConvert() }
                }
                if convertNamespace == .custom {
                    TextField("Custom namespace seed", text: $convertCustomSeed,
                              prompt: Text("Seed string for custom namespace"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                        .onChange(of: convertCustomSeed) { _, _ in recomputeConvert() }
                    Text("Custom namespace = first 16 bytes of SHA-1(seed).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = convertError {
                StatusBadge(message: error, isError: true)
            } else if !convertInput.isEmpty, !convertResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PaneHeader(title: convertVersion == .v5 ? "UUIDv5" : "UUIDv3") {
                        CopyButton(text: { convertResult })
                    }
                    Text(convertResult)
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text("RFC 4122 \(convertVersion == .v5 ? "v5 (SHA-1)" : "v3 (MD5)"): hash of namespace bytes + UTF-8 name, version/variant bits set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recomputeConvert() {
        convertError = nil
        convertResult = ""
        guard !convertInput.isEmpty else { return }
        guard let ns = UUIDKit.namespaceBytes(convertNamespace, customSeed: convertCustomSeed) else {
            convertError = "Enter a seed for the custom namespace."
            return
        }
        convertResult = UUIDKit.named(version: convertVersion == .v5 ? 5 : 3,
                                      namespace: ns, name: convertInput)
    }

    // MARK: - Validate

    private var validateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accepts canonical 8-4-4-4-12, urn:uuid:…, braced {…}, and bare 32-hex forms.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                PaneHeader(title: "Input") {
                    ToolButton(title: "Sample v1", systemImage: "wand.and.stars") {
                        validateInput = "8f2c7b3e-4d1a-11ef-9c6a-0242ac120002"
                    }
                    ToolButton(title: "Sample v4", systemImage: "wand.and.stars") {
                        validateInput = UUID().uuidString
                    }
                    ToolButton(title: "Sample v7", systemImage: "wand.and.stars") {
                        validateInput = "019247b0-8f23-7a41-9c0f-8a1b2c3d4e5f"
                    }
                    ToolButton(title: "Clear") { validateInput = "" }
                }
                CodeEditor(text: $validateInput, placeholder: "Paste a UUID to inspect…")
                    .frame(minHeight: 70)
            }

            validateReport
        }
    }

    private var trimmedValidate: String {
        validateInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var validateReport: some View {
        let input = trimmedValidate
        if !input.isEmpty {
            switch UUIDKit.parse(input) {
            case .failure(let err):
                StatusBadge(message: "Not a UUID: \(err.message)", isError: true)
            case .success(let info):
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(message: "Valid UUID · version \(UUIDKit.versionName(info.version))")
                    Text("Variant: \(info.variantName)")
                        .font(.callout)
                    if info.isNil { Text("Nil UUID (all zeros)").font(.callout).foregroundStyle(.secondary) }
                    if info.isMax { Text("Max UUID (all ones)").font(.callout).foregroundStyle(.secondary) }
                    if let ts = info.timestamp {
                        Text("Timestamp: \(Self.detailFormatter.string(from: ts)) UTC")
                            .font(.callout)
                        Text("Relative: \(Self.relative(to: ts))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let cs = info.clockSeq {
                        Text("Clock sequence: \(cs)")
                            .font(.callout)
                    }
                    if let mac = info.nodeMAC {
                        Text("Node: \(mac)\(info.multicastBit == true ? " (multicast bit set — randomized node)" : "")")
                            .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: - Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste any representation; get every common form.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                PaneHeader(title: "Input") {}
                CodeEditor(text: Binding(
                    get: { formatInput },
                    set: { formatInput = $0; recomputeFormat() }
                ), placeholder: "Paste a UUID in any format…")
                    .frame(minHeight: 70)
            }

            if formatInput.isEmpty == false {
                HStack(spacing: 12) {
                    Toggle("Uppercase", isOn: $formatUppercase)
                        .onChange(of: formatUppercase) { _, _ in recomputeFormat() }
                }
            }

            if let error = formatError {
                StatusBadge(message: "Not a UUID: \(error)", isError: true)
            } else if let info = formatResult {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(UUIDKit.Format.allCases) { fmt in
                        let rendered = fmt.render(canonical: info.normalized, uppercase: formatUppercase)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(fmt.rawValue)
                                .font(.callout)
                                .frame(width: 130, alignment: .leading)
                            Text(rendered)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            CopyButton(text: { rendered }, label: "Copy")
                        }
                        Divider()
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func recomputeFormat() {
        formatError = nil
        formatResult = nil
        let input = formatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        switch UUIDKit.parse(input) {
        case .failure(let err):
            formatError = err.message
        case .success(let info):
            formatResult = info
        }
    }

    // MARK: - Shared controls

    private func namedInputs(namespace: Binding<UUIDKit.Namespace>,
                             seed: Binding<String>,
                             name: Binding<String>,
                             seedHint: String,
                             note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Picker("Namespace", selection: namespace) {
                    ForEach(UUIDKit.Namespace.allCases) { ns in Text(ns.rawValue).tag(ns) }
                }
                .frame(maxWidth: 220)
                TextField("Name", text: name, prompt: Text("Name to hash"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            if namespace.wrappedValue == .custom {
                TextField("Custom namespace seed", text: seed,
                          prompt: Text("Seed string for custom namespace"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                Text(seedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Date helpers

    private static let detailFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func relative(to date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let absInterval = abs(interval)
        let parts: [(Int, String)] = [
            (3_600 * 24 * 365, "year"), (3_600 * 24 * 30, "month"),
            (3_600 * 24 * 7, "week"), (3_600 * 24, "day"),
            (3_600, "hour"), (60, "minute"), (1, "second"),
        ]
        for (seconds, label) in parts where absInterval >= Double(seconds) {
            let value = Int(absInterval / Double(seconds))
            let plural = value == 1 ? label : "\(label)s"
            return interval >= 0 ? "\(value) \(plural) ago" : "in \(value) \(plural)"
        }
        return "now"
    }
}
