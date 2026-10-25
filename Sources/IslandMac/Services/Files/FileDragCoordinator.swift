import AppKit
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

private final class PromiseCompletion: @unchecked Sendable {
    let call: (Error?) -> Void
    init(_ call: @escaping (Error?) -> Void) { self.call = call }
}

private final class PromiseProviderBox: @unchecked Sendable {
    let provider: NSFilePromiseProvider
    init(_ provider: NSFilePromiseProvider) { self.provider = provider }
}

@MainActor private final class DragAttempt {
    let id: UUID
    nonisolated let name: String
    var gate = DeliveryGate()
    init(item: ShelfItem) { id = item.id; name = item.displayName }
}

@MainActor final class FileDropHostingView: NSHostingView<IslandRootView> {
    var onDragActive: ((Bool) -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    required init(rootView: IslandRootView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        onDragActive?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { fileURLs(sender).isEmpty ? [] : .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragActive?(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }
    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

struct FileDragSource: NSViewRepresentable {
    let item: ShelfItem
    let access: NativeFileAccess
    let select: () -> Void
    func makeNSView(context: Context) -> DragView { DragView(item: item, access: access, select: select) }
    func updateNSView(_ view: DragView, context: Context) { view.item = item; view.select = select }
}

@MainActor final class DragView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var item: ShelfItem
    let access: NativeFileAccess
    var select: () -> Void
    private var activeAttempt: DragAttempt?
    init(item: ShelfItem, access: NativeFileAccess, select: @escaping () -> Void) {
        self.item = item; self.access = access; self.select = select
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func mouseDown(with event: NSEvent) { select() }
    override func mouseDragged(with event: NSEvent) {
        guard item.isAvailable else { return }
        let attempt = DragAttempt(item: item)
        activeAttempt = attempt
        let provider = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: self)
        provider.userInfo = attempt
        let drag = NSDraggingItem(pasteboardWriter: provider)
        let type = UTType(filenameExtension: (item.displayName as NSString).pathExtension) ?? .data
        drag.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(for: type))
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? DragAttempt)?.name ?? "File"
    }
    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let completion = PromiseCompletion(completionHandler)
        let box = PromiseProviderBox(provider)
        Task { @MainActor in
            guard let attempt = box.provider.userInfo as? DragAttempt else {
                completion.call(CocoaError(.fileWriteUnknown)); return
            }
            guard attempt.gate.receipt != .cancelled else {
                completion.call(CocoaError(.userCancelled)); return
            }
            do {
                try await access.writePromise(for: attempt.id, to: url)
                let wasConfirmed = attempt.gate.receipt == .confirmed
                let receipt = attempt.gate.markWriteVerified()
                completion.call(receipt == .cancelled ? CocoaError(.userCancelled) : nil)
                if !wasConfirmed && receipt == .confirmed { access.finishDelivery(attempt.id, receipt: .confirmed) }
            } catch {
                _ = attempt.gate.markWriteFailed()
                completion.call(error)
            }
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        guard let attempt = activeAttempt else { return }
        activeAttempt = nil
        let wasConfirmed = attempt.gate.receipt == .confirmed
        let receipt = attempt.gate.end(acceptedCopy: operation.contains(.copy))
        if !wasConfirmed && receipt == .confirmed { access.finishDelivery(attempt.id, receipt: .confirmed) }
    }
}
