public enum IslandFeature: String, CaseIterable, Sendable { case home, agents, music, files, terminal, settings }
public enum IslandMode: Equatable, Sendable { case hidden, home, feature(IslandFeature), prompt, drop }
public enum IslandTimer: Equatable, Sendable { case open, close }
public enum IslandEffect: Equatable, Sendable { case schedule(IslandTimer, token: UInt64, milliseconds: Int) }
public enum IslandEvent: Sendable {
    case pointerEntered, pointerExited, timer(IslandTimer, token: UInt64), show(IslandFeature), hide
    case inputChanged(Bool), dragChanged(Bool), pendingChanged(Int), fullScreenChanged(Bool), openPrompt
}
public struct IslandState: Equatable, Sendable {
    public var mode: IslandMode = .hidden
    public var pendingCount = 0
    public var inputActive = false
    public var dragActive = false
    public var fullScreen = false
    public var pointerInside = false
    public var generation: UInt64 = 0
    public var settings = IslandSettings()
    public init() {}
}
public enum IslandReducer {
    @discardableResult public static func reduce(state s: inout IslandState, event: IslandEvent) -> [IslandEffect] {
        if case let .timer(timer, token) = event {
            guard token == s.generation else { return [] }
            if timer == .open, s.pointerInside, !s.dragActive, s.mode == .hidden { s.mode = .home }
            if timer == .close, !s.pointerInside, !s.inputActive, !s.dragActive { s.mode = .hidden }
            return []
        }
        s.generation &+= 1
        switch event {
        case .pointerEntered:
            s.pointerInside = true
            if s.mode == .hidden { return [.schedule(.open, token: s.generation, milliseconds: s.settings.openDelayMilliseconds)] }
        case .pointerExited:
            s.pointerInside = false
            if !s.inputActive && !s.dragActive { return [.schedule(.close, token: s.generation, milliseconds: s.settings.closeDelayMilliseconds)] }
        case let .show(feature): s.mode = feature == .home ? .home : .feature(feature)
        case .hide: if !s.inputActive && !s.dragActive { s.mode = .hidden }
        case let .inputChanged(active):
            s.inputActive = active
            if !active && !s.pointerInside && !s.dragActive { return [.schedule(.close, token: s.generation, milliseconds: s.settings.closeDelayMilliseconds)] }
        case let .dragChanged(active): s.dragActive = active; s.mode = active ? .drop : .hidden
        case let .pendingChanged(count):
            s.pendingCount = max(0, count)
            if count > 0 && !s.inputActive && !s.dragActive && (!s.fullScreen || s.settings.fullScreenPrompts == .automatic) { s.mode = .prompt }
            if count == 0 && s.mode == .prompt { s.mode = .hidden }
        case let .fullScreenChanged(active): s.fullScreen = active
        case .openPrompt: if s.pendingCount > 0 && !s.dragActive { s.mode = .prompt }
        case .timer: break
        }
        return []
    }
}
