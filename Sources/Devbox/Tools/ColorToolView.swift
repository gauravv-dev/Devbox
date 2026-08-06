import SwiftUI

/// CSS color converter: hex (#RGB … #RRGGBBAA), rgb(), hsl() and the standard named colors.
struct ColorToolView: View {
    @State private var input = "#3498db"

    private var parsed: CSSColor? { CSSColor.parse(input) }
    private var hasInput: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ToolContainer(title: "Color Converter",
                      subtitle: "Convert CSS colors between hex, rgb(), hsl() and named colors.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("#RRGGBB, rgb(r, g, b), hsl(h, s%, l%) or e.g. cornflowerblue", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 480)
                    if parsed != nil {
                        StatusBadge(message: "Valid CSS color")
                    } else if hasInput {
                        StatusBadge(message: "Not a recognized CSS color", isError: true)
                    }
                }

                if let color = parsed {
                    HStack(alignment: .top, spacing: 24) {
                        swatch(for: color)
                        outputRows(for: color)
                    }
                }

                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func swatch(for color: CSSColor) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: color.r, green: color.g, blue: color.b, opacity: color.a))
                .frame(width: 160, height: 160)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.gray.opacity(0.35)))
                .overlay(
                    Text(color.prefersBlackText ? "Black text" : "White text")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color.prefersBlackText ? Color.black : Color.white)
                )
            Text(color.prefersBlackText ? "Black text reads best on this color" : "White text reads best on this color")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func outputRows(for color: CSSColor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OutputRow(label: "HEX", value: color.hexRGB)
            if color.hasAlpha {
                OutputRow(label: "HEX + alpha", value: color.hexRGBA)
            }
            OutputRow(label: color.hasAlpha ? "rgba()" : "rgb()", value: color.rgbString)
            OutputRow(label: color.hasAlpha ? "hsla()" : "hsl()", value: color.hslString)
        }
    }

    private struct OutputRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack(spacing: 8) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                CopyButton(text: { value })
            }
        }
    }
}

// MARK: - Parsing & conversion

private struct CSSColor {
    var r: Double // 0...1
    var g: Double // 0...1
    var b: Double // 0...1
    var a: Double // 0...1

    var hasAlpha: Bool { a < 1 }

    /// Whether black text is more readable on this color (blended over white first).
    var prefersBlackText: Bool {
        let wr = a * r + (1 - a)
        let wg = a * g + (1 - a)
        let wb = a * b + (1 - a)
        return 0.299 * wr + 0.587 * wg + 0.114 * wb > 0.6
    }

    private var rByte: Int { Int((r * 255).rounded()) }
    private var gByte: Int { Int((g * 255).rounded()) }
    private var bByte: Int { Int((b * 255).rounded()) }
    private var aByte: Int { Int((a * 255).rounded()) }

    var hexRGB: String { String(format: "#%02X%02X%02X", rByte, gByte, bByte) }

    var hexRGBA: String { String(format: "#%02X%02X%02X%02X", rByte, gByte, bByte, aByte) }

    var rgbString: String {
        if hasAlpha {
            return "rgba(\(rByte), \(gByte), \(bByte), \(Self.number((a * 1000).rounded() / 1000)))"
        }
        return "rgb(\(rByte), \(gByte), \(bByte))"
    }

    var hslString: String {
        let (h, s, l) = hsl
        let hue = Int(h.rounded()) % 360
        let sat = Self.number((s * 1000).rounded() / 10)
        let lig = Self.number((l * 1000).rounded() / 10)
        if hasAlpha {
            return "hsla(\(hue), \(sat)%, \(lig)%, \(Self.number((a * 1000).rounded() / 1000)))"
        }
        return "hsl(\(hue), \(sat)%, \(lig)%)"
    }

    /// Hue 0..<360, saturation and lightness 0...1.
    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        if maxC == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        return (h * 60, s, l)
    }

    // MARK: Parsing

    static func parse(_ raw: String) -> CSSColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("#") {
            return parseHex(String(s.dropFirst()))
        }
        let lower = s.lowercased()
        if lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") {
            return parseFunction(lower, isHSL: false)
        }
        if lower.hasPrefix("hsl(") || lower.hasPrefix("hsla(") {
            return parseFunction(lower, isHSL: true)
        }
        guard let value = namedColors[lower] else { return nil }
        return CSSColor(r: Double((value >> 16) & 0xFF) / 255,
                        g: Double((value >> 8) & 0xFF) / 255,
                        b: Double(value & 0xFF) / 255,
                        a: 1)
    }

    private static func parseHex(_ hex: String) -> CSSColor? {
        guard [3, 4, 6, 8].contains(hex.count) else { return nil }
        var digits: [Int] = []
        digits.reserveCapacity(hex.count)
        for ch in hex {
            guard let v = Int(String(ch), radix: 16) else { return nil }
            digits.append(v)
        }
        if digits.count <= 4 {
            digits = digits.flatMap { [$0, $0] }
        }
        return CSSColor(r: Double(digits[0] << 4 | digits[1]) / 255,
                        g: Double(digits[2] << 4 | digits[3]) / 255,
                        b: Double(digits[4] << 4 | digits[5]) / 255,
                        a: Double(digits[6] << 4 | digits[7]) / 255)
    }

    private static func parseFunction(_ s: String, isHSL: Bool) -> CSSColor? {
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }

        var alpha = 1.0
        if parts.count == 4 {
            guard let a = parseAlpha(parts[3]) else { return nil }
            alpha = a
        }

        if isHSL {
            guard let h = Double(parts[0]),
                  let sPct = parsePercent(parts[1]),
                  let lPct = parsePercent(parts[2]) else { return nil }
            var hue = h.truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
            let (r, g, b) = hslToRGB(h: hue, s: sPct / 100, l: lPct / 100)
            return CSSColor(r: r, g: g, b: b, a: alpha)
        } else {
            guard let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]),
                  (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) else { return nil }
            return CSSColor(r: r / 255, g: g / 255, b: b / 255, a: alpha)
        }
    }

    private static func parseAlpha(_ s: String) -> Double? {
        if s.hasSuffix("%") {
            guard let v = Double(String(s.dropLast())), (0...100).contains(v) else { return nil }
            return v / 100
        }
        guard let v = Double(s), (0...1).contains(v) else { return nil }
        return v
    }

    private static func parsePercent(_ s: String) -> Double? {
        guard s.hasSuffix("%"),
              let v = Double(String(s.dropLast())),
              (0...100).contains(v) else { return nil }
        return v
    }

    /// h in 0..<360, s and l in 0...1.
    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var rgb: (Double, Double, Double)
        switch hp {
        case 0..<1: rgb = (c, x, 0)
        case 1..<2: rgb = (x, c, 0)
        case 2..<3: rgb = (0, c, x)
        case 3..<4: rgb = (0, x, c)
        case 4..<5: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        let m = l - c / 2
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    /// Formats a number trimming trailing zeros ("50", "33.3", "0.5").
    private static func number(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: Named colors (full CSS set, including rebeccapurple)

    static let namedColors: [String: Int] = [
        "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF, "aquamarine": 0x7FFFD4,
        "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4, "black": 0x000000,
        "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
        "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00, "chocolate": 0xD2691E,
        "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC, "crimson": 0xDC143C,
        "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B, "darkgoldenrod": 0xB8860B,
        "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B,
        "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F, "darkorange": 0xFF8C00, "darkorchid": 0x9932CC,
        "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F, "darkslateblue": 0x483D8B,
        "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F, "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3,
        "deeppink": 0xFF1493, "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969,
        "dodgerblue": 0x1E90FF, "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22,
        "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF, "gold": 0xFFD700,
        "goldenrod": 0xDAA520, "gray": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F,
        "grey": 0x808080, "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C,
        "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C, "lavender": 0xE6E6FA,
        "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6,
        "lightcoral": 0xF08080, "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3,
        "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A,
        "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA, "lightslategray": 0x778899, "lightslategrey": 0x778899,
        "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0, "lime": 0x00FF00, "limegreen": 0x32CD32,
        "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000, "mediumaquamarine": 0x66CDAA,
        "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3, "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371,
        "mediumslateblue": 0x7B68EE, "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC, "mediumvioletred": 0xC71585,
        "midnightblue": 0x191970, "mintcream": 0xF5FFFA, "mistyrose": 0xFFE4E1, "moccasin": 0xFFE4B5,
        "navajowhite": 0xFFDEAD, "navy": 0x000080, "oldlace": 0xFDF5E6, "olive": 0x808000,
        "olivedrab": 0x6B8E23, "orange": 0xFFA500, "orangered": 0xFF4500, "orchid": 0xDA70D6,
        "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE, "palevioletred": 0xDB7093,
        "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9, "peru": 0xCD853F, "pink": 0xFFC0CB,
        "plum": 0xDDA0DD, "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399,
        "red": 0xFF0000, "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1, "saddlebrown": 0x8B4513,
        "salmon": 0xFA8072, "sandybrown": 0xF4A460, "seagreen": 0x2E8B57, "seashell": 0xFFF5EE,
        "sienna": 0xA0522D, "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD,
        "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA, "springgreen": 0x00FF7F,
        "steelblue": 0x4682B4, "tan": 0xD2B48C, "teal": 0x008080, "thistle": 0xD8BFD8,
        "tomato": 0xFF6347, "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3,
        "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00, "yellowgreen": 0x9ACD32,
    ]
}
