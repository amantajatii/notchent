import Testing
@testable import IslandCore

struct PromptQueueTests {
    private let session = SessionID(ownerInstanceID: "owned", pid: 11, processStartTime: 1, terminalSessionKey: "pane-a")
    @Test func fifoAndClosePreservesHead() {
        var q = PromptQueue()
        let a = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "a"), revision: 1, text: "A", choices: [], acceptsText: true)
        let b = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "b"), revision: 1, text: "B", choices: [], acceptsText: true)
        q.receive(a); q.receive(b)
        #expect(q.head?.id == a.id)
        q.dismissPresentation()
        #expect(q.head?.id == a.id)
        q.resolve(a.id)
        #expect(q.head?.id == b.id)
    }
    @Test func resolutionAndExitRemoveStale() {
        var q = PromptQueue()
        let a = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "a"), revision: 1, text: "A", choices: [], acceptsText: true)
        q.receive(a); q.resolve(a.id)
        #expect(q.prompt(a.id) == nil)
        q.receive(a); q.sessionExited(session)
        #expect(q.count == 0)
    }
}

extension PromptQueueTests {
    @Test func revisionDoesNotReorderAndResolvedCannotReappear() {
        var q = PromptQueue()
        func p(_ id: String, _ revision: UInt64) -> AgentPrompt {
            AgentPrompt(id: PromptID(sessionID: session, localRequestID: id), revision: revision, text: "rev \(revision)", choices: [], acceptsText: true)
        }
        q.receive(p("a", 1)); q.receive(p("b", 1)); q.receive(p("a", 3)); q.receive(p("a", 2))
        #expect(q.head?.revision == 3)
        q.resolve(PromptID(sessionID: session, localRequestID: "a")); q.receive(p("a", 4))
        #expect(q.head?.id == PromptID(sessionID: session, localRequestID: "b")); #expect(q.count == 1)
    }
}
