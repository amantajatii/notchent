import AppKit
import SwiftUI
import Testing
@testable import IslandMac

@MainActor struct AgentChatInputTests {
    @Test func hostedEditorHasUsableWidthAndPreservesText() async throws {
        let draft = AgentChatDraft()
        draft.text = "Ready to send"
        let host = NSHostingView(rootView: AgentChatInput(draft: draft, placeholder: "Message", send: {}).frame(width: 360, height: 36))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 36)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        func editor(in view: NSView) -> ChatTextView? {
            if let editor = view as? ChatTextView { return editor }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let textView = try #require(editor(in: host))
        #expect(textView.bounds.width > 300)
        #expect(textView.string == draft.text && textView.isEditable)
    }
    @Test func nativePasteAttachesAnImageAndLockedEditorIgnoresPaste() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        board.setData(try #require(bitmap.representation(using: .png, properties: [:])), forType: .png)
        let draft = AgentChatDraft()
        let editor = ChatTextView()
        editor.isRichText = false
        editor.pasteImages = { _ in draft.pasteImages(from: board) }
        editor.paste(nil)
        #expect(draft.images.count == 1 && editor.string.isEmpty)
        editor.isEditable = false
        editor.paste(nil)
        #expect(draft.images.count == 1)
    }
    @Test func commandVPastesThroughTheNativeEditor() throws {
        let editor = ChatTextView()
        var pasted = false
        editor.pasteImages = { _ in pasted = true; return true }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
        #expect(editor.performKeyEquivalent(with: event))
        #expect(pasted)
    }
    @Test func editingUpdatesDraftAndReturnUsesTheSendAction() {
        let draft = AgentChatDraft()
        var submissions = 0
        let input = AgentChatInput(draft: draft, placeholder: "Message", send: { submissions += 1 })
        let coordinator = input.makeCoordinator()
        let editor = ChatTextView()
        editor.string = "Message from the native editor"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(draft.text == editor.string && draft.canSubmit)
        #expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(submissions == 1)
        #expect(!coordinator.textView(editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    }
    @Test func textPasteFallsThroughWithoutChangingAttachments() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("A normal text paste", forType: .string)
        let draft = AgentChatDraft()
        #expect(!draft.pasteImages(from: board))
        #expect(draft.images.isEmpty && draft.status == nil)
    }
}
