import Testing
import IslandCore
@testable import IslandMac

private struct ConfirmingAdapter: AgentAdapter {
    let route: AgentRoute
    func events() -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    func validate(sessionID: SessionID) async throws -> AgentRoute { route }
    func respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt { .confirmed }
    func openOrigin(sessionID: SessionID) async throws { throw AgentRoutingError.unavailable }
}

@MainActor struct AgentRegistryTests {
    @Test func responsePublishesPendingAndReturnRouteWithoutPolling() async {
        let id = SessionID(ownerInstanceID: "test", pid: 10, processStartTime: 1, terminalSessionKey: "pane")
        let route = AgentRoute(sessionID: id, kind: .codex, capabilities: AgentCapabilities(readPrompt: true, sendResponse: true), permissionGranted: true)
        let coordinator = AgentCoordinator()
        await coordinator.register(ConfirmingAdapter(route: route), for: .codex)
        await coordinator.ingest(.route(route))
        let prompt = AgentPrompt(id: PromptID(sessionID: id, localRequestID: "1"), revision: 1, text: "Synthetic core routing request", choices: [], acceptsText: true)
        await coordinator.ingest(.prompt(prompt, kind: .codex))
        var state = IslandState()
        _ = IslandReducer.reduce(state: &state, event: .show(.terminal))
        _ = IslandReducer.reduce(state: &state, event: .pendingChanged(1))
        _ = IslandReducer.reduce(state: &state, event: .openPrompt)
        var counts: [Int] = []
        let registry = AgentRegistry(coordinator: coordinator) { count in
            counts.append(count)
            _ = IslandReducer.reduce(state: &state, event: .pendingChanged(count))
        }
        // Registry polling is never started. Await only the explicit response operation.
        await registry.respond(.text("reply"), to: prompt).value
        #expect(counts == [0]); #expect(registry.pendingCount == 0)
        #expect(registry.prompt == nil); #expect(state.mode == .feature(.terminal))
    }
}
