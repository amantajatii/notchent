public struct PromptQueue: Sendable {
    private var pending: [AgentPrompt] = []
    private var resolved: Set<PromptID> = []
    public init() {}
    public var head: AgentPrompt? { pending.first }
    public var count: Int { pending.count }
    public func prompt(_ id: PromptID) -> AgentPrompt? { pending.first { $0.id == id } }
    public mutating func receive(_ prompt: AgentPrompt) {
        guard !resolved.contains(prompt.id) else { return }
        if let index = pending.firstIndex(where: { $0.id == prompt.id }) {
            guard pending[index].sessionID == prompt.sessionID, prompt.revision > pending[index].revision else { return }
            pending[index] = prompt
        } else { pending.append(prompt) }
    }
    public mutating func resolve(_ id: PromptID) { pending.removeAll { $0.id == id }; resolved.insert(id) }
    public mutating func sessionExited(_ id: SessionID) {
        for prompt in pending where prompt.sessionID == id { resolved.insert(prompt.id) }
        pending.removeAll { $0.sessionID == id }
    }
    public func dismissPresentation() {} // Closing presentation is never resolution.
}
