import CoreGraphics

public enum IslandFeature: String, CaseIterable, Sendable { case home, agents, music, files, terminal, settings }
public enum IslandMode: Equatable, Sendable { case hidden, mini, home, feature(IslandFeature), prompt, drop, completion }
public enum IslandTimer: Equatable, Sendable { case open, close }
public enum IslandEffect: Equatable, Sendable { case schedule(IslandTimer, token: UInt64, milliseconds: Int), cancelTimer }
public enum IslandEvent: Sendable {
    case pointerEntered, pointerExited, timer(IslandTimer, token: UInt64), show(IslandFeature), reveal(IslandFeature), hide
    case agentCompleted, filesDropped, shelfDragEnded
    case inputChanged(Bool), dragChanged(Bool), pendingChanged(Int), fullScreenChanged(Bool), openPrompt, closePrompt
}
public struct IslandState: Equatable, Sendable {
    public var showsPromptBanner: Bool { pendingCount > 0 && mode == .feature(.terminal) && !fullScreen }
    public var promptReturnMode: IslandMode?
    public var showsPendingAffordance: Bool { pendingCount > 0 }
    public var mode: IslandMode = .hidden
    public var pendingCount = 0
    public var inputActive = false
    public var dragActive = false
    public var filesPinned = false
    public var fullScreen = false
    public var pointerInside = false
    public var scheduledTransition: IslandTimer?
    public var generation: UInt64 = 0
    public var settings = IslandSettings()
    public init() {}
}
public enum IslandReducer {
    private static func cancel(_ s: inout IslandState) -> [IslandEffect] {
        guard s.scheduledTransition != nil else { return [] }
        s.generation &+= 1
        s.scheduledTransition = nil
        return [.cancelTimer]
    }
    private static func schedule(_ kind: IslandTimer, _ s: inout IslandState) -> [IslandEffect] {
        s.generation &+= 1
        s.scheduledTransition = kind
        return [.schedule(kind, token: s.generation, milliseconds: kind == .open ? s.settings.openDelayMilliseconds : s.settings.closeDelayMilliseconds)]
    }
    private static func closeIfOutside(_ s: inout IslandState) -> [IslandEffect] {
        if s.filesPinned { return cancel(&s) }
        if s.mode == .prompt && s.pendingCount > 0 { return cancel(&s) }
        guard s.mode != .hidden, !s.pointerInside, !s.inputActive, !s.dragActive else { return cancel(&s) }
        return schedule(.close, &s)
    }
    @discardableResult public static func reduce(state s: inout IslandState, event: IslandEvent) -> [IslandEffect] {
        switch event {
        case let .timer(timer, token):
            guard token == s.generation, s.scheduledTransition == timer else { return [] }
            s.scheduledTransition = nil
            if timer == .open, s.pointerInside, !s.dragActive, s.mode == .hidden { s.mode = .mini }
            if timer == .close, !s.pointerInside, !s.inputActive, !s.dragActive { s.mode = .hidden }
        case .pointerEntered:
            s.pointerInside = true
            return s.mode == .hidden ? schedule(.open, &s) : cancel(&s)
        case .pointerExited:
            s.pointerInside = false
            return closeIfOutside(&s)
        case let .show(feature), let .reveal(feature):
            s.promptReturnMode = nil
            s.mode = feature == .home ? .home : .feature(feature)
            if case .reveal = event, !s.pointerInside, !s.inputActive, !s.dragActive {
                s.generation &+= 1
                s.scheduledTransition = .close
                return [.schedule(.close, token: s.generation, milliseconds: max(5000, s.settings.closeDelayMilliseconds))]
            }
            return closeIfOutside(&s)
        case .agentCompleted:
            guard (s.mode == .hidden || s.mode == .completion), !s.inputActive, !s.dragActive,
                  s.pendingCount == 0, !s.pointerInside,
                  !s.fullScreen || s.settings.fullScreenPrompts == .automatic else { return [] }
            s.mode = .completion
            s.generation &+= 1; s.scheduledTransition = .close
            return [.schedule(.close, token: s.generation, milliseconds: 5000)]
        case .hide:
            if !s.inputActive && !s.dragActive { s.filesPinned = false; s.mode = .hidden; return cancel(&s) }
        case .filesDropped:
            s.filesPinned = true; s.dragActive = false; s.mode = .feature(.files)
            return cancel(&s)
        case .shelfDragEnded:
            if s.filesPinned { s.filesPinned = false; s.mode = .hidden; return cancel(&s) }
        case let .inputChanged(active):
            s.inputActive = active
            return active ? cancel(&s) : closeIfOutside(&s)
        case let .dragChanged(active):
            if active { s.filesPinned = false }
            s.dragActive = active; s.mode = active ? .drop : .hidden
            return cancel(&s)
        case let .pendingChanged(count):
            let previous = s.pendingCount
            s.pendingCount = max(0, count)
            if count > previous && s.mode != .feature(.terminal) && !s.inputActive && !s.dragActive && (!s.fullScreen || s.settings.fullScreenPrompts == .automatic) {
                s.mode = .prompt
                return closeIfOutside(&s)
            }
            if count == 0 && s.mode == .prompt { s.mode = s.promptReturnMode ?? .hidden; s.promptReturnMode = nil; return cancel(&s) }
            // Count-only updates must not alter an existing hover deadline.
        case let .fullScreenChanged(active): s.fullScreen = active
        case .closePrompt:
            guard s.mode == .prompt else { return [] }
            s.mode = s.promptReturnMode ?? .hidden; s.promptReturnMode = nil
            return closeIfOutside(&s)
        case .openPrompt:
            if s.pendingCount > 0 && !s.dragActive { if s.mode != .prompt { s.promptReturnMode = s.mode }; s.mode = .prompt; return closeIfOutside(&s) }
        }
        return []
    }
}

public enum FullScreenAssessment {
    /// WindowServer can redact or omit windows without Screen Recording. Unknown is conservative.
    public static func isFullScreen(windowBounds: [CGRect]?, screen: CGRect) -> Bool {
        guard let windowBounds, !windowBounds.isEmpty else { return true }
        return windowBounds.contains { bounds in
            bounds.insetBy(dx: -2, dy: -2).contains(screen)
        }
    }
}
