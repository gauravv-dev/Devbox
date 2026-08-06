import SwiftUI
import AppKit

/// Monospaced multi-line editor backed by NSTextView.
///
/// Use for both inputs (editable: true) and outputs (editable: false — still selectable).
struct CodeEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var editable: Bool = true

    var body: some View {
        CodeEditorRepresentable(text: $text, editable: editable)
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !placeholder.isEmpty && editable {
                    Text(placeholder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.25)))
    }
}

struct CodeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = editable
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.isEditable != editable {
            textView.isEditable = editable
        }
        if textView.string != text {
            context.coordinator.programmatic = true
            textView.string = text
            context.coordinator.programmatic = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorRepresentable
        var programmatic = false

        init(_ parent: CodeEditorRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !programmatic, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
