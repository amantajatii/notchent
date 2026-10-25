import AppKit
import IslandCore
import UniformTypeIdentifiers

@MainActor
private final class SampleDragView: NSTextField, NSDraggingSource, NSFilePromiseProviderDelegate {
    var source: URL!
    var promisesFile = false
    var report: ((String) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let writer: NSPasteboardWriting = promisesFile ? NSFilePromiseProvider(fileType: UTType.plainText.identifier, delegate: self) : source as NSURL
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: NSImage(named: NSImage.multipleDocumentsName))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { "island-promised-sample.txt" }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            // Write independent known harmless bytes, avoiding any dependency on source lifetime.
            let bytes = Data("Native Island harmless drag sample v1\n".utf8)
            try bytes.write(to: url, options: .withoutOverwriting)
            guard try Data(contentsOf: url) == bytes else { throw CocoaError(.fileWriteUnknown) }
            completionHandler(nil)
            Task { @MainActor [weak self] in self?.report?("Promised destination write completed and bytes verified. Source retained; live consumer acceptance remains separate.") }
        } catch {
            completionHandler(error)
            Task { @MainActor [weak self] in self?.report?("Promised destination write failed. Receipt failed; source retained.") }
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // An empty operation cannot distinguish Escape cancellation from a rejecting target.
        let receipt: DeliveryReceipt = .unconfirmed
        report?("Native drag ended: operation=\(operation.rawValue), receipt=\(receipt.rawValue), retain=\(!canRemoveShelfCopy(receipt: receipt)). Empty operation means cancelled OR rejected; copy acceptance is not consumer acknowledgement.")
    }
}

@MainActor
final class DragProbe: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "No drag attempted. Source retained.")
    private var source: URL!
    private var target: URL!
    static func run() -> Never {
        let app = NSApplication.shared
        let probe = DragProbe()
        app.setActivationPolicy(.regular)
        app.delegate = probe
        withExtendedLifetime(probe) { app.run() }
        exit(0)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("IslandDragProbe-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            source = root.appendingPathComponent("island-harmless-sample.txt")
            target = root.appendingPathComponent("FinderTarget", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Data("Native Island harmless drag sample v1\n".utf8).write(to: source, options: .atomic)
        } catch { fputs("Could not create owned drag fixture.\n", stderr); NSApp.terminate(nil); return }
        let drag = SampleDragView(labelWithString: "DRAG THIS SAMPLE → Finder target folder")
        drag.source = source
        drag.report = { [weak self] message in self?.status.stringValue = message; print(message) }
        let promise = SampleDragView(labelWithString: "DRAG PROMISED SAMPLE → Finder target folder")
        promise.source = source
        promise.promisesFile = true
        promise.report = drag.report
        let stack = NSStackView(views: [
            drag, promise,
            NSTextField(wrappingLabelWithString: "Copy: open Finder target and drag into it. Cancel: press Escape during drag. Rejected target: drop on this instruction label (does not accept files). All paths retain source."),
            NSButton(title: "Open owned Finder target", target: self, action: #selector(openTarget)),
            NSButton(title: "Compare copied bytes", target: self, action: #selector(compare)), status
        ])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 680, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Island Probe — drag receipt"
        window.contentView = stack
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func openTarget() { NSWorkspace.shared.open(target) }
    @objc private func compare() {
        do {
            let original = try Data(contentsOf: source)
            let copied = try Data(contentsOf: target.appendingPathComponent(source.lastPathComponent))
            status.stringValue = original == copied ? "Destination bytes match. Source retained; this probe comparison is not a general consumer acknowledgement." : "Destination bytes differ. Source retained."
        } catch { status.stringValue = "Copy missing or unreadable. Source retained." }
        print(status.stringValue)
    }
}
