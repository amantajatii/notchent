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
        updatePillAtRest(screen)
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
    /// The resting pill follows the setting and the screen's notch. Full-screen state is deliberately
    /// ignored: without Screen Recording it reads as "full screen" all the time and would hide the pill.
    private func updatePillAtRest(_ screen: NSScreen) {
        let hasNotch = screen.auxiliaryTopLeftArea != nil
        let atRest = shell.settings.pillVisibility.showsAtRest(screenHasNotch: hasNotch)
        if atRest != shell.state.pillAtRest { send(.pillAtRestChanged(atRest)) }
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
            // The content had started fading out; bring it back for the same mode.
            if shell.surface.reveal.hiding { shell.surface.reveal = ContentReveal(id: shell.surface.reveal.id &+ 1) }
        }
        shell.presentedMode = shell.state.mode
        panel.inputEnabled = shell.state.mode == .prompt || shell.state.inputActive || shell.state.mode == .feature(.terminal) || shell.state.mode == .feature(.agents)
        if !panel.isVisible, measuredMode != shell.presentedMode || measuredSize.width <= 1 || measuredSize.height <= 1, let screen {
            // A readable first viewport lets SwiftUI mount before its first size report.
            let initial = shell.presentedMode == .mini ? CGSize(width: miniIslandWidth(screen), height: miniIslandHeight(screen)) : shell.presentedMode == .hidden ? CGSize(width: 220, height: 44) : (shell.presentedMode == .completion ? CGSize(width: 320, height: 52) : (shell.presentedMode == .home ? CGSize(width: 560, height: 194) : CGSize(width: 700, height: 440)))
            targetFrame = PanelGeometry.panelRect(screen: screen.frame, size: initial)
            panel.setFrame(windowFrame(targetFrame), display: false)
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
        animate(to: frame.size, alpha: 1, duration: reduceMotion ? 0.1 : Self.springDuration, screen: screen, closingGeneration: nil)
    }

    private func closePanel() {
        guard panel.isVisible, !closing else { return }
        closing = true
        motionGeneration &+= 1
        let generation = motionGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let screen else { panel.orderOut(nil); closing = false; return }
        shell.surface.reveal.hiding = true
        let closedSize = shell.presentedMode == .mini ? CGSize(width: shell.surface.size?.width ?? panel.frame.width, height: 0) : CGSize(width: 160, height: 0)
        if !reduceMotion { shell.surface.opacity = 1 }
        animate(to: reduceMotion ? shell.surface.size ?? panel.frame.size : closedSize, alpha: reduceMotion ? 0 : 1,
                duration: reduceMotion ? 0.1 : 0.34, screen: screen, closingGeneration: generation, delay: reduceMotion ? 0 : 0.08)
    }

    private func animate(to size: CGSize, alpha: CGFloat, duration: TimeInterval, screen: NSScreen, closingGeneration: UInt64?, delay: CFTimeInterval = 0) {
        displayLink?.invalidate()
        let from = shell.surface.size ?? panel.frame.size
        panel.setFrame(windowFrame(PanelGeometry.transitionViewport(screen: screen.frame, from: from, to: size)), display: true)
        updateMousePassThrough()
        motion = Motion(screen: screen.frame, from: from, to: size, alpha: CGFloat(shell.surface.opacity),
                        targetAlpha: alpha, start: CACurrentMediaTime() + delay, duration: duration, closingGeneration: closingGeneration)
        let link = screen.displayLink(target: self, selector: #selector(stepMotion(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func stepMotion(_ link: CADisplayLink) {
        guard link === displayLink, let motion else { link.invalidate(); return }
        let seconds = max(0, CACurrentMediaTime() - motion.start)
        let elapsed = min(1, seconds / motion.duration)
        // Opening and resizing spring (slight overshoot); collapsing eases in without a bounce.
        let springs = motion.closingGeneration == nil && motion.duration > 0.2
        let progress = springs ? Self.springProgress(seconds) : (motion.closingGeneration == nil ? 1 - pow(1 - elapsed, 3) : elapsed * elapsed * (3 - 2 * elapsed))
        shell.surface.size = CGSize(width: max(0, motion.from.width + (motion.to.width - motion.from.width) * progress),
                                    height: max(0, motion.from.height + (motion.to.height - motion.from.height) * progress))
        shell.surface.opacity = Double(motion.alpha + (motion.targetAlpha - motion.alpha) * CGFloat(min(1, elapsed * 2)))
        updateMousePassThrough()
        guard elapsed >= 1 else { return }
        link.invalidate(); displayLink = nil; self.motion = nil
        shell.surface.size = motion.to
        if let generation = motion.closingGeneration, generation == motionGeneration {
            panel.orderOut(nil); shell.presentedMode = .hidden; closing = false
        } else {
            panel.setFrame(windowFrame(PanelGeometry.panelRect(screen: motion.screen, size: motion.to)), display: true)
        }
    }
    /// Seconds a spring takes to settle within a fraction of a point.
    private static let springDuration = 0.6
    /// Damped spring step response: 0 at rest, 1 at target, a little overshoot in between.
    static func springProgress(_ t: Double, response: Double = IslandDesign.shapeResponse, damping: Double = IslandDesign.shapeDamping) -> Double {
        guard t < springDuration else { return 1 }
        let omega = 2 * Double.pi / response
        let damped = omega * (1 - damping * damping).squareRoot()
        let envelope = exp(-damping * omega * t)
        return 1 - envelope * (cos(damped * t) + damping * omega / damped * sin(damped * t))
    }
    /// The window is larger than the surface so the spring's overshoot is never clipped.
    private func windowFrame(_ surface: CGRect) -> CGRect {
        let margin = IslandDesign.windowMargin
        return CGRect(x: surface.minX - margin, y: surface.minY - margin, width: surface.width + 2 * margin, height: surface.height + margin)
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
                    MiniIslandView(shell: shell, spotify: shell.spotify, artwork: shell.artwork)
                } else if mode == .completion {
                    CompletionNoticeView(shell: shell, registry: shell.agents)
                } else if mode == .drop {
                    DropZoneView(shell: shell)
                } else if mode == .prompt {
                    PromptView(registry: shell.agents, shell: shell)
                } else {
                    navigation
                    PageReveal(state: shell.surface) { content }
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
        IslandNavigation(selected: selectedFeature, title: { shell.text($0.rawValue) }) { shell.dispatch?(.show($0)) }
    }
    @ViewBuilder private var content: some View {
        let feature = selectedFeature
        if let native = shell.retainedNativeViews[feature] { RetainedNativeView(view: native) }
        else if let view = shell.featureViews[feature] { view }
        else if feature == .home { HomeView(shell: shell, spotify: shell.spotify) }
        else if feature == .music { MusicView(shell: shell, spotify: shell.spotify) }
        else {
            IslandEmptyState(title: shell.text(feature == .agents ? "agentsUnavailable" : feature == .files ? "filesUnavailable" : "terminalUnavailable"),
                             symbol: IslandNavigation.symbol(for: feature))
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

/// The resting pill. While a track plays it shows the cover, the title (where no camera notch hides it)
/// and a level meter tinted with the cover's colour.
private struct MiniIslandView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    @ObservedObject var artwork: ArtworkPaletteStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let hoverGrowth: CGFloat = 6
    /// Gap from the inner edge of the shoulders to the cover and the meter.
    private static let edgePadding: CGFloat = 16
    private static let itemSpacing: CGFloat = 8
    private var screen: NSScreen? { NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main }

    var body: some View {
        let height = screen.map(miniIslandHeight) ?? 24
        let hasNotch = screen?.auxiliaryTopLeftArea != nil
        let playing = spotify.snapshot.playback == .playing
        let showsTitle = playing && !hasNotch && spotify.snapshot.title != nil
        let base = screen.map(miniIslandWidth) ?? 236
        let grow = shell.state.pointerInside ? Self.hoverGrowth : 0
        // Cover and meter share one slot size, so the title sits on the pill's true centre.
        let slot = min(22, max(14, height - 8))
        Button { shell.dispatch?(.show(.home)) } label: {
            HStack(spacing: Self.itemSpacing) {
                if playing {
                    SpotifyArtwork(url: spotify.snapshot.artworkURL, size: slot)
                    if showsTitle, let title = spotify.snapshot.title {
                        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                    LevelMeter(tint: artwork.palette?.primary.color ?? .white, paused: reduceMotion).frame(width: slot)
                }
            }
            // Playing or not, the pill keeps the normal width; a long title truncates instead of widening it.
            .padding(.horizontal, Self.edgePadding + grow)
            .frame(width: base + 2 * grow, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shell.text("open"))
    }
}

/// Four soft bars that bounce while music plays.
private struct LevelMeter: View {
    let tint: SwiftUI.Color
    let paused: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: paused)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 4)
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(tint)
                        .frame(width: 2.5, height: paused ? 8 : CGFloat(5 + ((phase + index * 3) % 4) * 3))
                        .animation(.easeInOut(duration: 0.22), value: phase)
                }
            }.frame(height: 16)
        }
    }
}
