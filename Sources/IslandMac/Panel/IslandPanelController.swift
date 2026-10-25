import AppKit
import SwiftUI
import IslandCore
import SwiftTerm

@MainActor private final class IslandPanel: NSPanel {
    var inputEnabled = false
    override var canBecomeKey: Bool { inputEnabled }
    override var canBecomeMain: Bool { false }
}

@MainActor final class IslandPanelController {
    let shell: IslandShell
    private let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let pointer = PointerMonitor()
    private let fullScreen = FullScreenMonitor()
    private var transitionTask: Task<Void, Never>?
    var inspectionPinned = false
    private var inside = false
    private var dragHot = false
    private var idleDragChangeCount: Int?
    private var host: FileDropHostingView!
    private var screen: NSScreen? { NSScreen.screens.first { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] .map { CGDisplayIsBuiltin(($0 as! NSNumber).uint32Value) != 0 } ?? false } ?? NSScreen.main }
    init(shell: IslandShell) {
        self.shell = shell
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        host = FileDropHostingView(rootView: IslandRootView(shell: shell))
        host.onDragActive = { [weak self] active in self?.setDragHot(active) }
        host.onDropFiles = { [weak self] urls in
            guard let self else { return }
            shell.files.importURLs(urls, mode: shell.settings.fileStorage)
            self.setDragHot(false)
        }
        panel.contentView = host
        shell.dispatch = { [weak self] in self?.send($0) }
    }
    func start() {
        fullScreen.start(screenBounds: { [weak self] in
            guard let number = self?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }, onChange: { [weak self] in self?.send(.fullScreenChanged($0)) })
        pointer.start { [weak self] in self?.poll() }
    }
    func stop() { fullScreen.stop(); pointer.stop(); transitionTask?.cancel(); transitionTask = nil; shell.spotify.setActive(false); panel.orderOut(nil) }
    func send(_ event: IslandEvent) {
        if case .show(.files) = event { shell.files.refresh() }
        if case .show(.home) = event { shell.files.refresh() }
        // Refresh synchronously at request arrival instead of trusting a stale 500 ms sample.
        if case .pendingChanged = event { fullScreen.refresh() }
        if case .hide = event { inspectionPinned = false }
        let effects = IslandReducer.reduce(state: &shell.state, event: event)
        let musicActive = shell.state.mode == .home || shell.state.mode == .feature(.home) || shell.state.mode == .feature(.music)
        shell.spotify.setActive(musicActive)
        render()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.render()
        }
        for effect in effects {
            transitionTask?.cancel()
            transitionTask = nil
            if case let .schedule(kind, token, milliseconds) = effect {
                transitionTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(milliseconds)) } catch { return }
                    guard let self else { return }
                    if self.inspectionPinned && kind == .close { return }
                    self.send(.timer(kind, token: token))
                }
            }
        }
    }
    private func poll() {
        guard let screen else { return }
        let focusedTerminal = shell.state.mode == .feature(.terminal) && panel.isKeyWindow && panel.firstResponder is LocalProcessTerminalView
        if focusedTerminal != shell.state.inputActive { send(.inputChanged(focusedTerminal)) }
        let point = NSEvent.mouseLocation
        let trigger = PanelGeometry.triggerRect(screen: screen.frame, menuBarHeight: max(24, screen.safeAreaInsets.top, NSStatusBar.system.thickness))
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        let dragBoard = NSPasteboard(name: .drag)
        if !mouseDown { idleDragChangeCount = dragBoard.changeCount }
        let hasFileURLs = dragBoard.types?.contains(.fileURL) == true && dragBoard.changeCount != idleDragChangeCount
        let hoveringDropArea = trigger.contains(point) || (panel.isVisible && panel.frame.contains(point))
        setDragHot(mouseDown && hasFileURLs && hoveringDropArea)
        let next = trigger.contains(point) || (panel.isVisible && panel.frame.contains(point))
        if next != inside { inside = next; send(next ? .pointerEntered : .pointerExited) }
    }
    private func setDragHot(_ active: Bool) {
        guard dragHot != active else { return }
        dragHot = active
        send(.dragChanged(active))
    }
    private func render() {
        let visible = shell.state.mode != .hidden || shell.state.pendingCount > 0
        guard visible, let screen else { panel.orderOut(nil); return }
        panel.inputEnabled = shell.state.inputActive || shell.state.mode == .feature(.terminal) || shell.state.mode == .feature(.settings)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setFrame(PanelGeometry.panelRect(screen: screen.frame, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

struct IslandRootView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        VStack(spacing: 12) {
            if shell.state.showsPendingAffordance {
                Button { shell.dispatch?(.openPrompt) } label: {
                    Label("\(shell.text("pending")): \(shell.state.pendingCount)", systemImage: "bubble.left.fill")
                        .font(.caption.bold()).padding(8)
                }
            }
            if shell.state.mode == .hidden {
                EmptyView()
            } else if shell.state.mode == .drop {
                DropZoneView(shell: shell)
            } else if shell.state.mode == .prompt {
                Text(shell.text("promptUnavailable")).padding(24)
            } else {
                HStack(spacing: 18) {
                    ForEach(IslandFeature.allCases, id: \.self) { feature in
                        Button(shell.text(feature.rawValue)) { shell.dispatch?(.show(feature)) }
                    }
                }.font(.caption).foregroundStyle(.secondary)
                content
            }
        }
        .buttonStyle(.plain).padding(shell.state.mode == .hidden ? 0 : 18)
        .foregroundStyle(.white).background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .environment(\.locale, Locale(identifier: shell.settings.language.rawValue))
        .preferredColorScheme(.dark)
    }
    @ViewBuilder private var content: some View {
        let feature: IslandFeature = { if case let .feature(f) = shell.state.mode { return f }; return .home }()
        if let native = shell.retainedNativeViews[feature] { RetainedNativeView(view: native) }
        else if let view = shell.featureViews[feature] { view }
        else if feature == .settings { SettingsView(shell: shell) }
        else if feature == .home { HomeView(shell: shell, spotify: shell.spotify) }
        else if feature == .music { MusicView(shell: shell, spotify: shell.spotify) }
        else {
            Text(shell.text(feature == .music ? "musicUnavailable" : feature == .agents ? "agentsUnavailable" : feature == .files ? "filesUnavailable" : "terminalUnavailable"))
                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12).frame(width: 520)
        }
    }
}

/// Reparents a strongly owned view; dismantling this wrapper never ends a session.
private struct RetainedNativeView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
