import AppKit
import SwiftUI

struct AgentChatInput: NSViewRepresentable {
    @ObservedObject var draft: AgentChatDraft
    let placeholder: String
    var send: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        let text = ChatTextView()
        text.delegate = context.coordinator
        text.isRichText = false
        text.importsGraphics = false
        text.drawsBackground = false
        text.textColor = .white
        text.insertionPointColor = .white
        text.font = .systemFont(ofSize: 13)
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.allowsUndo = true
        text.setAccessibilityLabel(placeholder)
        scroll.documentView = text
        updateNSView(scroll, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = scroll.documentView as? ChatTextView else { return }
        if text.string != draft.text { text.string = draft.text }
        text.isEditable = !draft.sending && !draft.uncertain
        text.pasteImages = { draft.pasteImages(from: $0) }
        text.setAccessibilityLabel(placeholder)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentChatInput
        init(_ parent: AgentChatInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            parent.draft.text = text.string
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               !textView.hasMarkedText(), !NSEvent.modifierFlags.contains(.shift) {
                parent.send(); return true
            }
            return false
        }
    }
}

final class ChatTextView: NSTextView {
    var pasteImages: ((NSPasteboard) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        if pasteImages?(.general) == true { return }
        super.paste(sender)
    }
}
