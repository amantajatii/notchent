/// Tracks only terminals started by this app. Presentation changes never mutate it.
public struct TerminalLifecycle: Sendable {
    private var owned: Set<SessionID> = []
    private var running: Set<SessionID> = []
    private var closing: Set<SessionID> = []

    public init() {}
    public var hasRunningOwnedSessions: Bool { !running.isEmpty }
    public var shouldConfirmQuit: Bool { hasRunningOwnedSessions }
    public func contains(_ id: SessionID) -> Bool { owned.contains(id) }
    public func isRunning(_ id: SessionID) -> Bool { running.contains(id) }

    public mutating func open(_ id: SessionID) {
        owned.insert(id)
        running.insert(id)
    }
    public mutating func featureHidden() {}
    public mutating func featureSwitched() {}
    @discardableResult public mutating func close(_ id: SessionID) -> Bool {
        guard owned.contains(id), !closing.contains(id) else { return false }
        if running.contains(id) { closing.insert(id) }
        else { owned.remove(id) }
        return true
    }
    public mutating func processExited(_ id: SessionID) {
        running.remove(id)
        if closing.remove(id) != nil { owned.remove(id) }
    }
}
