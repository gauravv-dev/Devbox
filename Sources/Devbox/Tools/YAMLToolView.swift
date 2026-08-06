import Foundation
import SwiftUI
import Yams

/// YAML formatter and YAML ↔ JSON converter.
struct YAMLToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case formatYAML = "Format YAML"
        case yamlToJSON = "YAML → JSON"
        case jsonToYAML = "JSON → YAML"

        var id: String { rawValue }

        var outputFilename: String {
            switch self {
            case .formatYAML, .jsonToYAML: return "output.yaml"
            case .yamlToJSON: return "output.json"
            }
        }
    }

    @State private var input = ""
    @State private var output = ""
    @State private var mode: Mode = .formatYAML
    @State private var sortedKeys = false
    /// Error surfaced by the most recent conversion attempt; cleared on success.
    @State private var conversionError: String?

    var body: some View {
        ToolContainer(title: "YAML", subtitle: "Format YAML and convert between YAML and JSON.") {
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
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Toggle("Sort keys", isOn: $sortedKeys)
                .toggleStyle(.checkbox)

            Spacer()

            ToolButton(title: "Convert", systemImage: "arrow.left.arrow.right") { convert() }
                .disabled(!hasInput)
            ToolButton(title: "Sample") { input = Self.sample(for: mode) }
            ToolButton(title: "Clear") { clear() }
        }
    }

    // MARK: - Panes

    private var inputPane: some View {
        VStack(spacing: 6) {
            PaneHeader(title: "Input", badge: mode.rawValue) {
                OpenFileButton(text: $input)
            }
            CodeEditor(text: $input, placeholder: placeholder)
                .frame(minWidth: 320, minHeight: 160)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var outputPane: some View {
        VStack(spacing: 6) {
            PaneHeader(title: "Output", badge: output.isEmpty ? nil : "\(output.count) chars") {
                CopyButton(text: { output })
                SaveFileButton(text: { output }, filename: mode.outputFilename)
            }
            CodeEditor(text: $output, placeholder: "Output appears here", editable: false)
                .frame(minWidth: 320, minHeight: 160)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var placeholder: String {
        mode == .jsonToYAML ? "Paste JSON…" : "Paste YAML…"
    }

    // MARK: - Actions

    private func convert() {
        switch mode {
        case .formatYAML: formatYAML()
        case .yamlToJSON: yamlToJSON()
        case .jsonToYAML: jsonToYAML()
        }
    }

    private func formatYAML() {
        do {
            guard let node = try Yams.compose(yaml: input) else {
                output = ""
                conversionError = nil
                return
            }
            output = try Yams.serialize(node: node, indent: 2, width: -1, sortKeys: sortedKeys)
            conversionError = nil
        } catch {
            output = ""
            conversionError = Self.describe(error)
        }
    }

    private func yamlToJSON() {
        do {
            let object = try Yams.load(yaml: input)
            let normalized = YAMLJSONNormalizer.normalize(object)
            let data = try JSONSerialization.data(
                withJSONObject: normalized,
                options: [.prettyPrinted, .fragmentsAllowed]
            )
            output = String(data: data, encoding: .utf8) ?? ""
            conversionError = nil
        } catch {
            output = ""
            conversionError = Self.describe(error)
        }
    }

    private func jsonToYAML() {
        do {
            let object = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.allowFragments])
            output = try Yams.dump(object: object, indent: 2, width: -1, sortKeys: sortedKeys)
            conversionError = nil
        } catch {
            output = ""
            conversionError = "Invalid JSON: \(Self.describe(error))"
        }
    }

    private func clear() {
        input = ""
        output = ""
        conversionError = nil
    }

    // MARK: - Live validation

    private var validation: (message: String, isError: Bool)? {
        // Conversion errors take precedence so they stay visible while typing.
        if let conversionError {
            return (conversionError, true)
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch mode {
        case .formatYAML, .yamlToJSON:
            do {
                _ = try Yams.load(yaml: input)
                return ("Valid YAML", false)
            } catch {
                return ("Invalid YAML: \(Self.describe(error))", true)
            }
        case .jsonToYAML:
            do {
                _ = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.allowFragments])
                return ("Valid JSON", false)
            } catch {
                return ("Invalid JSON: \((error as NSError).localizedDescription)", true)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let yamlError = error as? Yams.YamlError {
            return yamlErrorMessage(yamlError)
        }
        return String(describing: error)
    }

    /// Compact one-line description of a YamlError, including line/column when available.
    private static func yamlErrorMessage(_ error: Yams.YamlError) -> String {
        switch error {
        case let .scanner(context, problem, mark, _),
             let .parser(context, problem, mark, _),
             let .composer(context, problem, mark, _):
            var message = "\(problem) at line \(mark.line), column \(mark.column)"
            if let context {
                let contextText = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !contextText.isEmpty {
                    message += " (\(contextText))"
                }
            }
            return message
        case let .reader(problem, _, _, _),
             let .writer(problem),
             let .emitter(problem),
             let .representer(problem):
            return problem
        default:
            return String(describing: error)
        }
    }

    // MARK: - Samples

    private static func sample(for mode: Mode) -> String {
        switch mode {
        case .formatYAML, .yamlToJSON:
            return """
            app: Devbox
            version: 1
            stable: true
            tags:
              - yaml
              - formatter
            settings:
              indent: 2
              sort_keys: false
            """
        case .jsonToYAML:
            return """
            {
              "app": "Devbox",
              "version": 1,
              "stable": true,
              "tags": ["yaml", "formatter"]
            }
            """
        }
    }
}

// MARK: - YAML → JSON normalization

/// Converts the heterogeneous `Any?` produced by `Yams.load` into JSON-safe values:
/// dictionary keys become strings, nested containers recurse, scalars pass through.
private enum YAMLJSONNormalizer {
    static func normalize(_ value: Any?) -> Any {
        guard let value else { return NSNull() }

        if let dictionary = value as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            result.reserveCapacity(dictionary.count)
            for (key, element) in dictionary {
                let keyString = (key as? String) ?? String(describing: key)
                result[keyString] = normalize(element)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(normalize)
        }
        // Exact Bool check first: YAML booleans arrive as Swift Bool, and a numeric
        // NSNumber cast `as? Bool` would flip 0/1 into false/true.
        if value is Bool { return value }
        if let number = value as? NSNumber { return number }
        if let string = value as? String { return string }
        if let date = value as? Date { return date.timeIntervalSince1970 }
        if value is NSNull { return NSNull() }
        if let int = value as? Int { return int }
        if let double = value as? Double { return double }
        return String(describing: value)
    }
}
