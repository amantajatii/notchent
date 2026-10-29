import AppKit
import SwiftUI
import IslandCore
import SwiftTerm
import QuartzCore

@MainActor private final class IslandPanel: NSPanel {
    var inputEnabled = false
    override var canBecomeKey: Bool { inputEnabled }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor final class IslandPanelController: NSObject {
    let shell: IslandShell
    private let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let pointer = PointerMonitor()
    private let fullScreen = FullScreenMonitor()
    private var transitionTask: Task<Void, Never>?
    var inspectionPinned = false
    private var inside = false
    private var dragHot = false
    private var fileDrag = FileDragActivation(idleChangeCount: NSPasteboard(name: .drag).changeCount)
    private var host: FileDropHostingView!
    private var activeScreen: NSScreen?
    private var targetFrame: CGRect = .zero
    private var motionGeneration: UInt64 = 0
    private var closing = false
    private var displayLink: CADisplayLink?
    private var motion: Motion?
    private var measuredMode: IslandMode = .hidden
    private var measuredSize: CGSize = .zero
    private struct Motion {
        let screen: CGRect
        let from: CGSize
        let to: CGSize
        let alpha: CGFloat
        let targetAlpha: CGFloat
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let closingGeneration: UInt64?
    }
    private var screen: NSScreen? { activeScreen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main }
    init(shell: IslandShell) {
        self.shell = shell
        super.init()
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        host = FileDropHostingView(rootView: IslandRootView(shell: shell))
        host.sizingOptions = []
        host.onDragActive = { [weak self] active in
            if active || NSEvent.pressedMouseButtons & 1 == 0 { self?.setDragHot(active) }
        }
        host.acceptsDragLocation = { [weak self] point in self?.containsSurfacePoint(point) ?? false }
        host.onDropFiles = { [weak self] urls in
            guard let self else { return }
            shell.files.importURLs(urls, mode: shell.settings.fileStorage)
            _ = self.fileDrag.update(mouseDown: false, hasFileURLs: false, changeCount: NSPasteboard(name: .drag).changeCount)
            self.setDragHot(false)
            self.send(.filesDropped)
        }
        panel.contentView = host
        shell.dispatch = { [weak self] in self?.send($0) }
        shell.contentSizeDidChange = { [weak self] mode, size in
            guard let self, mode == self.shell.presentedMode, size.width > 1, size.height > 1 else { return }
            self.measuredMode = mode; self.measuredSize = size
            self.layoutPanel(size: size)
        }
    }
    func start() {
        fullScreen.start(screenBounds: { [weak self] in
            guard let number = self?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }, onChange: { [weak self] in self?.send(.fullScreenChanged($0)) })
        pointer.start { [weak self] in self?.poll() }
    }
    func stop() {
        fullScreen.stop(); pointer.stop(); transitionTask?.cancel(); transitionTask = nil
        motionGeneration &+= 1; displayLink?.invalidate(); displayLink = nil; motion = nil
        shell.spotify.setActive(false); panel.orderOut(nil)
    }
    func send(_ event: IslandEvent) {
        if case .show(.files) = event { shell.files.refresh() }
        if case .show(.home) = event { shell.files.refresh() }
        if case .reveal(.home) = event { shell.files.refresh() }
        // Refresh synchronously at request arrival instead of trusting a stale 500 ms sample.
        if case .pendingChanged = event { fullScreen.refresh() }
        if case .hide = event { inspectionPinned = false }
        let previousMode = shell.state.mode
        var effects = IslandReducer.reduce(state: &shell.state, event: event)
        if case .pointerEntered = event, closing, shell.state.scheduledTransition == .open {
            _ = IslandReducer.reduce(state: &shell.state, event: .timer(.open, token: shell.state.generation))
            effects = [.cancelTimer]
        }
        let musicActive = shell.state.mode == .mini || shell.state.mode == .home || shell.state.mode == .feature(.home) || shell.state.mode == .feature(.music)
        shell.spotify.setActive(musicActive)
        render()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.render()
            if previousMode == .prompt, let self, self.shell.state.mode == .feature(.terminal),
               let id = self.shell.terminals.selectedID {
                self.panel.makeKey()
                self.panel.makeFirstResponder(self.shell.terminals.view(for: id))
            }
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
        if !panel.isVisible {
            activeScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        }
        guard let screen else { return }
        let focusedTerminal = panel.isKeyWindow && ((shell.state.mode == .feature(.terminal) && panel.firstResponder is LocalProcessTerminalView) || ((shell.state.mode == .prompt || shell.state.mode == .feature(.agents)) && panel.firstResponder is NSTextView))
        if focusedTerminal != shell.state.inputActive { send(.inputChanged(focusedTerminal)) }
        let point = NSEvent.mouseLocation
        if panel.isVisible { updateMousePassThrough() }
        let trigger = PanelGeometry.triggerRect(screen: screen.frame, menuBarHeight: max(24, screen.safeAreaInsets.top, NSStatusBar.system.thickness))
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        let dragBoard = NSPasteboard(name: .drag)
        let draggingFile = fileDrag.update(mouseDown: mouseDown, hasFileURLs: dragBoard.types?.contains(.fileURL) == true, changeCount: dragBoard.changeCount)
        let expanded = panel.isVisible ? targetFrame : nil
        let hoveringDropArea = PanelGeometry.containsPointer(point, trigger: trigger, expandedPanel: expanded)
        setDragHot(draggingFile)
        let next = hoveringDropArea
        if next != inside { inside = next; send(next ? .pointerEntered : .pointerExited) }
    }
    private func setDragHot(_ active: Bool) {
        guard dragHot != active else { return }
        dragHot = active
        send(.dragChanged(active))
    }
    private func render() {
        let visible = shell.state.mode != .hidden || shell.state.pendingCount > 0
        guard visible else { closePanel(); return }
        if closing {
            motionGeneration &+= 1; displayLink?.invalidate(); displayLink = nil; motion = nil; closing = false
        }
        shell.presentedMode = shell.state.mode
        panel.inputEnabled = shell.state.mode == .prompt || shell.state.inputActive || shell.state.mode == .feature(.terminal) || shell.state.mode == .feature(.settings) || shell.state.mode == .feature(.agents)
        if !panel.isVisible, measuredMode != shell.presentedMode || measuredSize.width <= 1 || measuredSize.height <= 1, let screen {
            // A readable first viewport lets SwiftUI mount before its first size report.
            let initial = shell.presentedMode == .mini ? CGSize(width: miniIslandWidth(screen), height: miniIslandHeight(screen)) : shell.presentedMode == .hidden ? CGSize(width: 220, height: 44) : (shell.presentedMode == .completion ? CGSize(width: 320, height: 52) : (shell.presentedMode == .home ? CGSize(width: 560, height: 194) : CGSize(width: 700, height: 440)))
            targetFrame = PanelGeometry.panelRect(screen: screen.frame, size: initial)
            panel.setFrame(targetFrame, display: false)
            shell.surface.size = shell.presentedMode == .mini && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? CGSize(width: targetFrame.width, height: 0) : targetFrame.size
            shell.surface.opacity = shell.presentedMode == .mini ? 0 : 1
            panel.alphaValue = 1; panel.ignoresMouseEvents = true
            host.rootView = IslandRootView(shell: shell)
            panel.orderFrontRegardless()
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }
        if measuredMode == shell.presentedMode { layoutPanel(size: measuredSize) }
    }

    private func layoutPanel(size: CGSize) {
        guard shell.state.mode != .hidden || shell.state.pendingCount > 0,
              size.width > 1, size.height > 1, let screen else { return }
        let frame = PanelGeometry.panelRect(screen: screen.frame, size: size)
        guard frame != targetFrame || !panel.isVisible || closing || shell.surface.opacity < 0.999 else { return }
        let opening = !panel.isVisible || closing || shell.surface.opacity < 0.999
        motionGeneration &+= 1
        closing = false
        targetFrame = frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            shell.surface.opacity = 0
            shell.surface.size = reduceMotion ? frame.size : CGSize(width: 160, height: 26)
        }
        if reduceMotion { shell.surface.size = frame.size }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        animate(to: frame.size, alpha: 1, duration: reduceMotion ? 0.1 : (opening ? 0.48 : 0.42), screen: screen, closingGeneration: nil)
    }

    private func closePanel() {
        guard panel.isVisible, !closing else { return }
        closing = true
        motionGeneration &+= 1
        let generation = motionGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let screen else { panel.orderOut(nil); closing = false; return }
        let closedSize = shell.presentedMode == .mini ? CGSize(width: shell.surface.size?.width ?? panel.frame.width, height: 0) : CGSize(width: 160, height: 0)
        if !reduceMotion { shell.surface.opacity = 1 }
        animate(to: reduceMotion ? shell.surface.size ?? panel.frame.size : closedSize, alpha: reduceMotion ? 0 : 1,
                duration: reduceMotion ? 0.1 : 0.42, screen: screen, closingGeneration: generation)
    }

    private func animate(to size: CGSize, alpha: CGFloat, duration: TimeInterval, screen: NSScreen, closingGeneration: UInt64?) {
        displayLink?.invalidate()
        let from = shell.surface.size ?? panel.frame.size
        panel.setFrame(PanelGeometry.transitionViewport(screen: screen.frame, from: from, to: size), display: true)
        updateMousePassThrough()
        motion = Motion(screen: screen.frame, from: from, to: size, alpha: CGFloat(shell.surface.opacity),
                        targetAlpha: alpha, start: CACurrentMediaTime(), duration: duration, closingGeneration: closingGeneration)
        let link = screen.displayLink(target: self, selector: #selector(stepMotion(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func stepMotion(_ link: CADisplayLink) {
        guard link === displayLink, let motion else { link.invalidate(); return }
        let elapsed = min(1, max(0, (CACurrentMediaTime() - motion.start) / motion.duration))
        let progress = 1 - pow(1 - elapsed, 3)
        let visualFrame = PanelGeometry.transitionRect(screen: motion.screen, from: motion.from, to: motion.to, progress: progress)
        shell.surface.size = visualFrame.size
        shell.surface.opacity = Double(motion.alpha + (motion.targetAlpha - motion.alpha) * CGFloat(progress))
        updateMousePassThrough()
        guard elapsed >= 1 else { return }
        link.invalidate(); displayLink = nil; self.motion = nil
        if let generation = motion.closingGeneration, generation == motionGeneration {
            panel.orderOut(nil); shell.presentedMode = .hidden; closing = false
        } else {
            panel.setFrame(PanelGeometry.panelRect(screen: motion.screen, size: motion.to), display: true)
        }
    }
    private func updateMousePassThrough() {
        panel.ignoresMouseEvents = !containsSurfacePoint(NSEvent.mouseLocation)
    }
    private func containsSurfacePoint(_ point: CGPoint) -> Bool {
        guard let screen, shell.surface.opacity >= 0.05 else { return false }
        let size = shell.surface.size ?? targetFrame.size
        let frame = PanelGeometry.panelRect(screen: screen.frame, size: size)
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        return IslandSilhouette().path(in: CGRect(origin: .zero, size: size)).contains(local)
    }
}

struct IslandMeasurement: Equatable {
    let mode: IslandMode
    let size: CGSize
}
struct IslandContentSize: PreferenceKey {
    static let defaultValue = IslandMeasurement(mode: .hidden, size: .zero)
    static func reduce(value: inout IslandMeasurement, nextValue: () -> IslandMeasurement) {
        let next = nextValue()
        if next.size.width > 1, next.size.height > 1 { value = next }
    }
}

struct IslandRootView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        let mode = shell.presentedMode
        IslandSurface(state: shell.surface) {
            VStack(spacing: 16) {
                if shell.state.showsPendingAffordance && mode != .prompt && mode != .mini {
                    PromptBannerView(shell: shell)
                }
                if mode == .hidden {
                    EmptyView()
                } else if mode == .mini {
                    MiniIslandView(shell: shell, spotify: shell.spotify)
                } else if mode == .completion {
                    CompletionNoticeView(shell: shell, registry: shell.agents)
                } else if mode == .drop {
                    DropZoneView(shell: shell)
                } else if mode == .prompt {
                    PromptView(registry: shell.agents, shell: shell)
                } else {
                    navigation
                    content
                }
            }
            .buttonStyle(IslandControlStyle()).padding((mode == .hidden || mode == .mini) ? 0 : (mode == .completion ? 12 : 20))
            .fixedSize()
            .background(GeometryReader { geometry in
                Color.clear.preference(key: IslandContentSize.self, value: IslandMeasurement(mode: mode, size: geometry.size))
            })
            .onPreferenceChange(IslandContentSize.self) { measurement in shell.contentSizeDidChange?(measurement.mode, measurement.size) }
        }
        .foregroundStyle(.white)
        .environment(\.locale, Locale(identifier: shell.settings.language.rawValue))
        .preferredColorScheme(.dark)
    }
    private var selectedFeature: IslandFeature {
        if case let .feature(feature) = shell.presentedMode { return feature }
        return .home
    }
    private var navigation: some View {
        ZStack {
            HStack(spacing: 4) {
                ForEach([IslandFeature.home, .agents, .music, .files, .terminal], id: \.self) { feature in
                    Button { shell.dispatch?(.show(feature)) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: symbol(for: feature)).font(.system(size: 12, weight: .medium))
                            Text(shell.text(feature.rawValue)).font(.system(size: 11, weight: selectedFeature == feature ? .semibold : .medium))
                        }
                        .foregroundStyle(selectedFeature == feature ? .white : Color(white: 0.62))
                        .frame(width: 74, height: 32)
                        .contentShape(Rectangle())
                    }.help(shell.text(feature.rawValue)).accessibilityLabel(shell.text(feature.rawValue))
                }
            }
            .background {
                let features: [IslandFeature] = [.home, .agents, .music, .files, .terminal]
                let index = features.firstIndex(of: selectedFeature)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 74, height: 32)
                    .offset(x: CGFloat((index ?? 2) - 2) * 78)
                    .opacity(index == nil ? 0 : 1)
                    .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.42), value: index)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 4) {
                Button {
                    shell.dispatch?(.inputChanged(false))
                    shell.dispatch?(.hide)
                } label: { Image(systemName: "minus").frame(width: 30, height: 30).foregroundStyle(Color(white: 0.62)) }
                    .help(shell.text("hide")).accessibilityLabel(shell.text("hide"))
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.frame(width: 520, height: 32)
    }
    private func symbol(for feature: IslandFeature) -> String {
        switch feature {
        case .home: "square.grid.2x2"
        case .agents: "square.3.layers.3d"
        case .music: "music.note"
        case .files: "tray"
        case .terminal: "terminal"
        case .settings: "slider.horizontal.3"
        }
    }
    @ViewBuilder private var content: some View {
        let feature = selectedFeature
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

private struct IslandControlStyle: ButtonStyle {
    @MainActor private final class HoverState: ObservableObject { @Published var active = false }
    func makeBody(configuration: Configuration) -> some View { Control(configuration: configuration) }
    private struct Control: View {
        let configuration: ButtonStyleConfiguration
        @StateObject private var hover = HoverState()
        var body: some View {
            configuration.label
                .background(.white.opacity(hover.active ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 9))
                .opacity(configuration.isPressed ? 0.65 : 1)
                .onHover { hover.active = $0 }
                .animation(.easeOut(duration: 0.12), value: hover.active)
        }
    }
}

/// Reparents a strongly owned view; dismantling this wrapper never ends a session.
private struct RetainedNativeView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private func miniIslandWidth(_ screen: NSScreen) -> CGFloat {
    guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return 236 }
    return max(236, right.minX - left.maxX + 80)
}

private func miniIslandHeight(_ screen: NSScreen) -> CGFloat {
    max(24, screen.safeAreaInsets.top, NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
}

private struct MiniIslandView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var screen: NSScreen? { NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main }
    var body: some View {
        Button { shell.dispatch?(.show(.home)) } label: {
            HStack(spacing: 6) {
                if spotify.snapshot.playback == .playing {
                    SpotifyArtwork(url: spotify.snapshot.artworkURL, size: 14)
                    Spacer(minLength: 0)
                    TimelineView(.animation(minimumInterval: 0.25, paused: reduceMotion)) { context in
                        let phase = Int(context.date.timeIntervalSinceReferenceDate * 4)
                        HStack(alignment: .center, spacing: 2) {
                            ForEach(0..<4) { index in
                                Capsule().fill(.green).frame(width: 2, height: CGFloat(reduceMotion ? 8 : 4 + ((phase + index * 3) % 4) * 3))
                            }
                        }.frame(height: 16)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(width: screen.map(miniIslandWidth) ?? 236, height: screen.map(miniIslandHeight) ?? 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shell.text("open"))
    }
}
