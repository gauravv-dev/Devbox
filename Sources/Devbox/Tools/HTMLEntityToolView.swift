import SwiftUI

/// HTML entity encoder/decoder with a built-in map of common named entities.
struct HTMLEntityToolView: View {
    enum Direction: String, CaseIterable, Identifiable {
        case escape = "Escape"
        case unescape = "Unescape"
        var id: String { rawValue }
    }

    @State private var direction: Direction = .escape
    @State private var minimalOnly = true
    @State private var input = ""
    @State private var output = ""
    @State private var warning = ""

    var body: some View {
        ToolContainer(title: "HTML Entities",
                      subtitle: "Escape and unescape HTML entities, including numeric references.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Picker("Direction", selection: $direction) {
                        ForEach(Direction.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)

                    if direction == .escape {
                        Toggle("Escape only minimal set", isOn: $minimalOnly)
                            .toggleStyle(.checkbox)
                    }
                    Spacer()
                }

                VSplitView {
                    VStack(alignment: .leading, spacing: 6) {
                        PaneHeader(title: direction == .escape ? "Plain text" : "HTML source") {}
                        CodeEditor(text: $input,
                                   placeholder: direction == .escape
                                       ? "Paste plain text to escape…"
                                       : "Paste HTML with entities to unescape…")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        PaneHeader(title: "Output") {
                            CopyButton(text: { output })
                            SaveFileButton(text: { output },
                                           filename: direction == .escape ? "escaped.html" : "unescaped.txt")
                        }
                        CodeEditor(text: $output, placeholder: "Output appears here…", editable: false)
                        if !warning.isEmpty {
                            StatusBadge(message: warning, isError: true)
                        }
                    }
                }
            }
            .padding(.top, 4)
            .onChange(of: input) { recompute() }
            .onChange(of: direction) { recompute() }
            .onChange(of: minimalOnly) { recompute() }
        }
    }

    private func recompute() {
        warning = ""
        if input.isEmpty {
            output = ""
            return
        }
        switch direction {
        case .escape:
            output = Self.escape(input, minimalOnly: minimalOnly)
        case .unescape:
            let (text, unrecognized) = Self.unescape(input)
            output = text
            if unrecognized > 0 {
                warning = unrecognized == 1
                    ? "1 unrecognized entity left unchanged"
                    : "\(unrecognized) unrecognized entities left unchanged"
            }
        }
    }

    // MARK: - Escape

    private static func escape(_ input: String, minimalOnly: Bool) -> String {
        var out = ""
        out.reserveCapacity(input.count + 16)
        for scalar in input.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default:
                if !minimalOnly && scalar.value > 127 {
                    out += String(format: "&#x%04X;", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    // MARK: - Unescape

    private static func unescape(_ input: String) -> (text: String, unrecognized: Int) {
        let scalars = Array(input.unicodeScalars)
        var out = ""
        out.reserveCapacity(input.count)
        var unrecognized = 0
        var i = 0
        while i < scalars.count {
            guard scalars[i] == "&" else {
                out.unicodeScalars.append(scalars[i])
                i += 1
                continue
            }
            // Look for a terminating ';' within a reasonable window.
            var end = i + 1
            while end < scalars.count && end - i <= 32 && scalars[end] != ";" {
                end += 1
            }
            guard end < scalars.count && scalars[end] == ";" else {
                out += "&"
                unrecognized += 1
                i += 1
                continue
            }
            let body = String(String.UnicodeScalarView(scalars[(i + 1)..<end]))
            if let decoded = decodeEntity(body) {
                out += decoded
            } else {
                out += "&" + body + ";"
                unrecognized += 1
            }
            i = end + 1
        }
        return (out, unrecognized)
    }

    private static func decodeEntity(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let rest = body.dropFirst()
            var value: UInt32?
            if rest.lowercased().hasPrefix("x") {
                value = UInt32(rest.dropFirst(), radix: 16)
            } else if rest.allSatisfy({ $0.isNumber }) && !rest.isEmpty {
                value = UInt32(rest)
            }
            guard let v = value, let scalar = Unicode.Scalar(v) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[body]
    }

    // MARK: - Named entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "zwnj": "\u{200C}", "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "sbquo": "\u{201A}", "bdquo": "\u{201E}",
        "times": "\u{00D7}", "divide": "\u{00F7}", "deg": "\u{00B0}", "plusmn": "\u{00B1}",
        "frac12": "\u{00BD}", "frac14": "\u{00BC}", "frac34": "\u{00BE}",
        "euro": "\u{20AC}", "pound": "\u{00A3}", "yen": "\u{00A5}", "cent": "\u{00A2}",
        "sect": "\u{00A7}", "para": "\u{00B6}", "middot": "\u{00B7}", "bull": "\u{2022}",
        "dagger": "\u{2020}", "Dagger": "\u{2021}", "permil": "\u{2030}",
        "lsaquo": "\u{2039}", "rsaquo": "\u{203A}",
        "curren": "\u{00A4}", "brvbar": "\u{00A6}", "uml": "\u{00A8}",
        "ordf": "\u{00AA}", "ordm": "\u{00BA}", "not": "\u{00AC}", "shy": "\u{00AD}", "macr": "\u{00AF}",
        "aelig": "\u{00E6}", "AElig": "\u{00C6}", "oelig": "\u{0153}", "OElig": "\u{0152}",
        "szlig": "\u{00DF}", "eth": "\u{00F0}", "ETH": "\u{00D0}",
        "thorn": "\u{00FE}", "THORN": "\u{00DE}", "fnof": "\u{0192}",
        "circ": "\u{02C6}", "tilde": "\u{02DC}",
        "Scaron": "\u{0160}", "scaron": "\u{0161}", "Yuml": "\u{0178}", "yuml": "\u{00FF}",
        "agrave": "\u{00E0}", "aacute": "\u{00E1}", "acirc": "\u{00E2}", "atilde": "\u{00E3}",
        "auml": "\u{00E4}", "aring": "\u{00E5}",
        "ccedil": "\u{00E7}",
        "egrave": "\u{00E8}", "eacute": "\u{00E9}", "ecirc": "\u{00EA}", "euml": "\u{00EB}",
        "igrave": "\u{00EC}", "iacute": "\u{00ED}", "icirc": "\u{00EE}", "iuml": "\u{00EF}",
        "ntilde": "\u{00F1}",
        "ograve": "\u{00F2}", "oacute": "\u{00F3}", "ocirc": "\u{00F4}", "otilde": "\u{00F5}",
        "ouml": "\u{00F6}", "oslash": "\u{00F8}",
        "ugrave": "\u{00F9}", "uacute": "\u{00FA}", "ucirc": "\u{00FB}", "uuml": "\u{00FC}",
        "yacute": "\u{00FD}",
    ]
}
