import SwiftUI

/// Type-erased wrapper so the registry can hold heterogeneous tool views.
struct ToolView: View {
    private let content: AnyView
    init<V: View>(@ViewBuilder _ content: () -> V) {
        self.content = AnyView(content())
    }
    var body: some View { content }
}

import AppKit

/// Container chrome shared by every tool: title block + content area.
struct ToolContainer<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            content
                .padding([.horizontal, .bottom], 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Header row for an input/output pane: title, optional stats badge, trailing actions.
struct PaneHeader<Actions: View>: View {
    var title: String
    var badge: String? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.15)))
            }
            Spacer()
            actions()
        }
    }
}

/// Small toolbar-style button.
struct ToolButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .controlSize(.small)
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

/// Copies the provided text and flashes a "Copied" confirmation.
struct CopyButton: View {
    var text: () -> String
    var label: String = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            Clipboard.copy(text())
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .controlSize(.small)
        .disabled(text().isEmpty)
    }
}

/// Opens a text file via NSOpenPanel and loads it into the bound text.
struct OpenFileButton: View {
    @Binding var text: String

    var body: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if #available(macOS 11.0, *) {
                panel.allowedContentTypes = [.json, .yaml, .plainText, .text, .utf8PlainText]
            }
            if panel.runModal() == .OK, let url = panel.url {
                if let s = try? String(contentsOf: url, encoding: .utf8) {
                    text = s
                } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
                    text = s
                }
            }
        } label: {
            Label("Open…", systemImage: "square.and.arrow.up")
        }
        .controlSize(.small)
    }
}

/// Saves text to a file via NSSavePanel.
struct SaveFileButton: View {
    var text: () -> String
    var filename: String = "output.txt"

    var body: some View {
        Button {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try? text().write(to: url, atomically: true, encoding: .utf8)
            }
        } label: {
            Label("Save…", systemImage: "square.and.arrow.down")
        }
        .controlSize(.small)
        .disabled(text().isEmpty)
    }
}

/// Colored status line: green check or red error text.
struct StatusBadge: View {
    var message: String
    var isError: Bool = false

    var body: some View {
        if !message.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                Text(message)
            }
            .font(.callout)
            .foregroundStyle(isError ? Color.red : Color.green)
            .textSelection(.enabled)
        }
    }
}
