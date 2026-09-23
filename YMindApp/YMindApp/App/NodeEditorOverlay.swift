import AppKit
import SwiftUI

struct NodeEditorOverlay: View {
    let screenRect: CGRect
    let isRoot: Bool
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NodeTextEditor(
            text: $text,
            isRoot: isRoot,
            onCommit: onCommit,
            onCancel: onCancel
        )
        .frame(
            width: max(screenRect.width, 80),
            height: max(screenRect.height, 36)
        )
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.tint, lineWidth: 2)
        }
        .position(x: screenRect.midX, y: screenRect.midY)
        .accessibilityLabel("编辑主题")
    }
}

private struct NodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isRoot: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        let textView = CommitTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.font = isRoot
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CommitTextView else {
            return
        }
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }
    }
}

private final class CommitTextView: NSTextView {
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    private var didRequestFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didRequestFocus else { return }
        didRequestFocus = true
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: string.utf16.count, length: 0))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.option) || modifiers.contains(.command) {
                insertText("\n", replacementRange: selectedRange())
            } else {
                onCommit()
            }
        case 53:
            onCancel()
        default:
            super.keyDown(with: event)
        }
    }
}
