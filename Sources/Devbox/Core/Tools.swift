import SwiftUI

enum ToolCategory: String, CaseIterable, Identifiable {
    case formats = "Formats"
    case encoders = "Encoders"
    case generators = "Generators"
    case text = "Text"

    var id: String { rawValue }
}

enum ToolKind: String, CaseIterable, Identifiable, Hashable {
    case json, yaml, jwt, base64, url, uuid, epoch, hash, regex, text, color, html, diff

    var id: String { rawValue }
}

struct DevTool: Identifiable {
    let id: ToolKind
    let name: String
    let icon: String
    let category: ToolCategory
    let keywords: [String]
    let builder: @MainActor () -> ToolView

    var id_string: String { id.rawValue }
}

extension DevTool {
    static let tools: [DevTool] = [
        DevTool(id: .json, name: "JSON", icon: "curlybraces", category: .formats,
                keywords: ["json", "format", "beautify", "minify", "validate", "pretty"]) { ToolView { JSONToolView() } },
        DevTool(id: .yaml, name: "YAML", icon: "list.bullet.indent", category: .formats,
                keywords: ["yaml", "yml", "format", "json", "convert", "validate"]) { ToolView { YAMLToolView() } },
        DevTool(id: .jwt, name: "JWT Decoder", icon: "key.fill", category: .formats,
                keywords: ["jwt", "token", "jose", "decode", "claims", "exp"]) { ToolView { JWTToolView() } },
        DevTool(id: .diff, name: "Diff", icon: "doc.on.doc", category: .formats,
                keywords: ["diff", "compare", "text", "changes", "myers"]) { ToolView { DiffToolView() } },
        DevTool(id: .base64, name: "Base64", icon: "textformat.abc", category: .encoders,
                keywords: ["base64", "encode", "decode", "b64", "url-safe"]) { ToolView { Base64ToolView() } },
        DevTool(id: .url, name: "URL Encode", icon: "link", category: .encoders,
                keywords: ["url", "uri", "encode", "decode", "percent", "query"]) { ToolView { URLToolView() } },
        DevTool(id: .html, name: "HTML Entities", icon: "chevron.left.forwardslash.chevron.right", category: .encoders,
                keywords: ["html", "entities", "escape", "unescape", "amp"]) { ToolView { HTMLEntityToolView() } },
        DevTool(id: .uuid, name: "UUID", icon: "barcode", category: .generators,
                keywords: ["uuid", "guid", "v4", "v5", "generate", "random"]) { ToolView { UUIDToolView() } },
        DevTool(id: .epoch, name: "Epoch / Timestamp", icon: "clock.fill", category: .generators,
                keywords: ["epoch", "unix", "timestamp", "date", "time", "convert"]) { ToolView { EpochToolView() } },
        DevTool(id: .hash, name: "Hashes", icon: "number.square.fill", category: .generators,
                keywords: ["hash", "sha256", "sha512", "md5", "hmac", "digest", "checksum"]) { ToolView { HashToolView() } },
        DevTool(id: .color, name: "Color Converter", icon: "paintpalette.fill", category: .generators,
                keywords: ["color", "hex", "rgb", "hsl", "convert", "css"]) { ToolView { ColorToolView() } },
        DevTool(id: .regex, name: "Regex Tester", icon: "asterisk", category: .text,
                keywords: ["regex", "regexp", "match", "replace", "pattern", "test"]) { ToolView { RegexToolView() } },
        DevTool(id: .text, name: "Text Transforms", icon: "textformat", category: .text,
                keywords: ["text", "case", "camel", "snake", "kebab", "sort", "reverse", "trim", "slug"]) { ToolView { TextToolView() } },
    ]
}
