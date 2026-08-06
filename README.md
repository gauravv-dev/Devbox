# Devbox

A native macOS developer toolbox — JSON, YAML, JWT, Base64, hashes, and more, fully offline.

Built with SwiftUI. No data leaves your machine.

## Tools

| Category | Tools |
|---|---|
| Formats | JSON formatter/validator, YAML formatter + YAML↔JSON, JWT decoder, Text diff |
| Encoders | Base64, URL encode/decode, HTML entities |
| Generators | UUID (v4/v5), Epoch/timestamp converter, Hashes (MD5/SHA/HMAC), Color converter |
| Text | Regex tester, Text transforms (case, sort, slug, …) |

## Build

Requires the Xcode Command Line Tools (Swift toolchain) — full Xcode not needed.

```sh
./build_app.sh        # release build → build/Devbox.app
open build/Devbox.app
```

Or develop directly:

```sh
swift build
swift run Devbox
```

## Layout

```
Sources/Devbox/
  DevboxApp.swift     # app entry + window
  Core/               # sidebar, tool registry, shared editor/chrome, diff engine
  Tools/              # one file per tool
```

Adding a tool: create `Sources/Devbox/Tools/MyToolView.swift`, then register it in
`Core/Tools.swift` (a `DevTool` entry with category, icon, and keywords).

## Notes

- Bundles are ad-hoc signed for local use.
- YAML via [Yams](https://github.com/jpsim/Yams); hashes via CryptoKit (MD5/SHA-1 vendored).
