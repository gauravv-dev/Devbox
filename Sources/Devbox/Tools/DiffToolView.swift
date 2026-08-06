import SwiftUI

/// Side-by-side text inputs with a live unified diff rendered from DiffEngine.
struct DiffToolView: View {
    @State private var original = ""
    @State private var modified = ""
    @State private var ignoreTrailingWhitespace = false
    @State private var ignoreCase = false
    @State private var rows: [DiffRow] = []
    @State private var tooLarge = false

    private var bothEmpty: Bool { original.isEmpty && modified.isEmpty }

    var body: some View {
        ToolContainer(title: "Diff",
                      subtitle: "Compare two texts line-by-line with a live unified diff.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Toggle("Ignore trailing whitespace", isOn: $ignoreTrailingWhitespace)
                        .toggleStyle(.checkbox)
                    Toggle("Ignore case", isOn: $ignoreCase)
                        .toggleStyle(.checkbox)
                    Spacer()
                    ToolButton(title: "Swap", systemImage: "arrow.left.arrow.right") {
                        let tmp = original
                        original = modified
                        modified = tmp
                        recompute()
                    }
                    ToolButton(title: "Clear", systemImage: "trash") {
                        original = ""
                        modified = ""
                        recompute()
                    }
                }

                HSplitView {
                    inputPane(title: "Original", text: $original)
                    inputPane(title: "Modified", text: $modified)
                }
                .frame(minHeight: 140)

                resultPane
            }
            .padding(.top, 4)
            .onChange(of: original) { recompute() }
            .onChange(of: modified) { recompute() }
            .onChange(of: ignoreTrailingWhitespace) { recompute() }
            .onChange(of: ignoreCase) { recompute() }
        }
    }

    // MARK: - Panes

    private func inputPane(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: title) {
                OpenFileButton(text: text)
            }
            CodeEditor(text: text, placeholder: "Paste or open \(title.lowercased()) text…")
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 140)
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Diff", badge: bothEmpty ? nil : summaryBadge) {
                CopyButton(text: { copyText }, label: "Copy diff")
            }

            if bothEmpty {
                VStack {
                    Spacer()
                    Text("Paste or open two texts to compare")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if tooLarge {
                StatusBadge(message: "Input too large for line diff", isError: true)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            DiffRowView(row: row)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.25)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived values

    private var summaryBadge: String {
        let added = rows.filter { $0.kind == .added }.count
        let removed = rows.filter { $0.kind == .removed }.count
        let unchanged = rows.filter { $0.kind == .same }.count
        return "+\(added) \u{2212}\(removed) \u{00B7} \(unchanged) unchanged"
    }

    private var copyText: String {
        rows.map { row in
            switch row.kind {
            case .same: return " " + row.text
            case .removed: return "-" + row.text
            case .added: return "+" + row.text
            }
        }
        .joined(separator: "\n")
    }

    // MARK: - Diff computation

    private func recompute() {
        guard !bothEmpty else {
            rows = []
            tooLarge = false
            return
        }
        let originalLines = DiffEngine.splitLines(original)
        let modifiedLines = DiffEngine.splitLines(modified)
        let a = originalLines.map(normalize)
        let b = modifiedLines.map(normalize)
        guard let changes = DiffEngine.diff(a: a, b: b) else {
            rows = []
            tooLarge = true
            return
        }
        tooLarge = false

        var built: [DiffRow] = []
        built.reserveCapacity(changes.count)
        var oi = 0
        var mi = 0
        for change in changes {
            switch change.kind {
            case .same:
                built.append(DiffRow(id: built.count, kind: .same, number: oi + 1, text: originalLines[oi]))
                oi += 1
                mi += 1
            case .removed:
                built.append(DiffRow(id: built.count, kind: .removed, number: oi + 1, text: originalLines[oi]))
                oi += 1
            case .added:
                built.append(DiffRow(id: built.count, kind: .added, number: mi + 1, text: modifiedLines[mi]))
                mi += 1
            }
        }
        rows = built
    }

    private func normalize(_ line: String) -> String {
        var result = line
        if ignoreTrailingWhitespace {
            while let last = result.last, last == " " || last == "\t" || last == "\r" {
                result.removeLast()
            }
        }
        if ignoreCase {
            result = result.lowercased()
        }
        return result
    }

    // MARK: - Row model

    struct DiffRow: Identifiable {
        let id: Int
        let kind: DiffEngine.ChangeKind
        let number: Int
        let text: String
    }
}

private struct DiffRowView: View {
    let row: DiffToolView.DiffRow

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(String(row.number))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(prefix)
                .frame(width: 16, alignment: .leading)
            Text(row.text)
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(minHeight: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var prefix: String {
        switch row.kind {
        case .same: return " "
        case .removed: return "\u{2212}"
        case .added: return "+"
        }
    }

    private var background: Color {
        switch row.kind {
        case .same: return .clear
        case .removed: return Color.red.opacity(0.15)
        case .added: return Color.green.opacity(0.15)
        }
    }
}
