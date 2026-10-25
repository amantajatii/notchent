import AppKit
import SwiftUI
import IslandCore

@MainActor private final class IslandPanel: NSPanel {
    var inputEnabled = false
    override var canBecomeKey: Bool { inputEnabled }
    override var canBecomeMain: Bool { false }
}

@MainActor final class IslandPanelController {
    let shell: IslandShell
    private let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let pointer = PointerMonitor()
    private var tasks: [Task<Void, Never>] = []
    private var inside = false
    private var host: NSHostingView<IslandRootView>!
    private var screen: NSScreen? { NSScreen.screens.first { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] .map { CGDisplayIsBuiltin(($0 as! NSNumber).uint32Value) != 0 } ?? false } ?? NSScreen.main }
    init(shell: IslandShell) {
        self.shell = shell
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        host = NSHostingView(rootView: IslandRootView(shell: shell))
        panel.contentView = host
        shell.dispatch = { [weak self] in self?.send($0) }
    }
    func start() { pointer.start { [weak self] in self?.poll() } }
    func stop() { pointer.stop(); tasks.forEach { $0.cancel() }; tasks.removeAll(); panel.orderOut(nil) }
    func send(_ event: IslandEvent) {
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        let effects = IslandReducer.reduce(state: &shell.state, event: event)
        render()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.render()
        }
        for case let .schedule(kind, token, milliseconds) in effects {
            tasks.append(Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(milliseconds)) } catch { return }
                self?.send(.timer(kind, token: token))
            })
        }
    }
    private func poll() {
        guard let screen else { return }
        let point = NSEvent.mouseLocation
        let trigger = PanelGeometry.triggerRect(screen: screen.frame, menuBarHeight: max(24, screen.safeAreaInsets.top, NSStatusBar.system.thickness))
        let next = trigger.contains(point) || (panel.isVisible && panel.frame.contains(point))
        if next != inside { inside = next; send(next ? .pointerEntered : .pointerExited) }
    }
    private func render() {
        let visible = shell.state.mode != .hidden || shell.state.pendingCount > 0
        guard visible, let screen else { panel.orderOut(nil); return }
        panel.inputEnabled = shell.state.inputActive || shell.state.mode == .feature(.settings)
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
            if shell.state.mode == .hidden {
                Button { shell.dispatch?(.openPrompt) } label: { Text("\(shell.state.pendingCount)").font(.caption.bold()).padding(8) }
            } else if shell.state.mode == .drop {
                Label(shell.text("drop"), systemImage: "tray.and.arrow.down").padding(28)
            } else if shell.state.mode == .prompt {
                Text(shell.text("promptUnavailable")).padding(24)
            } else {
                HStack(spacing: 18) {
                    ForEach(IslandFeature.allCases, id: \.self) { feature in
                        Button(shell.text(feature.rawValue)) { shell.dispatch?(.show(feature)) }
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if shell.state.inputActive && shell.state.pendingCount > 0 {
                    Button(shell.text("pending")) { shell.dispatch?(.openPrompt) }
                }
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
        else if feature == .home {
            HStack(alignment: .center, spacing: 30) {
                Label { VStack(alignment: .leading, spacing: 6) {
                    Text("Spotify").font(.headline)
                    Text(shell.text("musicUnavailable")).font(.caption).foregroundStyle(.secondary)
                } } icon: { Image(systemName: "music.note").font(.largeTitle).frame(width: 56, height: 56).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }
                VStack(alignment: .leading, spacing: 12) {
                    Button(shell.text("agents")) { shell.dispatch?(.show(.agents)) }
                    Button(shell.text("files")) { shell.dispatch?(.show(.files)) }
                }.font(.caption)
            }.frame(width: 520, alignment: .leading)
        } else {
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
