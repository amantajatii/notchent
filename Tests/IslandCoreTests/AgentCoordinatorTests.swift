import Testing
@testable import IslandCore

struct AgentCoordinatorTests {
    @Test func unsupportedAndStaleRoutesNeverSend() async {
        let coordinator = AgentCoordinator()
        let session = SessionID(ownerInstanceID: "owned", pid: 11, processStartTime: 1, terminalSessionKey: "a")
        let p = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "p"), revision: 1, text: "Prompt", choices: [], acceptsText: true)
        await coordinator.ingest(.prompt(p, kind: .codex))
        await #expect(throws: AgentRoutingError.self) { try await coordinator.respond(id: p.id, revision: 0, response: .text("yes")) }
        await #expect(throws: AgentRoutingError.self) { try await coordinator.respond(id: p.id, revision: 1, response: .text("yes")) }
    }
}

private actor RecordingAdapter: AgentAdapter {
    var route: AgentRoute
    var sent: [AgentPrompt] = []
    var receipt: ResponseReceipt = .confirmed
    var held = false
    var validating = false
    var continuation: CheckedContinuation<Void, Never>?
    init(_ route: AgentRoute) { self.route = route }
    nonisolated func events() -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    func validate(sessionID: SessionID) async throws -> AgentRoute {
        if held { validating = true; await withCheckedContinuation { continuation = $0 } }
        return route
    }
    func respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt { sent.append(prompt); return receipt }
    func openOrigin(sessionID: SessionID) async throws { throw AgentRoutingError.unavailable }
    func setRoute(_ value: AgentRoute) { route = value }
    func setReceipt(_ value: ResponseReceipt) { receipt = value }
    func hold() { held = true }
    func release() { held = false; continuation?.resume(); continuation = nil }
}

extension AgentCoordinatorTests {
    private func session(_ pid: Int32 = 11, birth: UInt64 = 1, pane: String = "a", owner: String = "owned") -> SessionID {
        SessionID(ownerInstanceID: owner, pid: pid, processStartTime: birth, terminalSessionKey: pane)
    }
    private func route(_ id: SessionID, permission: Bool = true, supported: Bool = true) -> AgentRoute {
        AgentRoute(sessionID: id, kind: .codex, capabilities: AgentCapabilities(readPrompt: supported, sendResponse: supported), permissionGranted: permission)
    }
    private func prompt(_ id: String, session: SessionID, revision: UInt64 = 1) -> AgentPrompt {
        AgentPrompt(id: PromptID(sessionID: session, localRequestID: id), revision: revision, text: "Original question", choices: [PromptChoice(id: "original-id", text: "Original choice")], acceptsText: true)
    }
    @Test func sameProjectTwoSessionsRoutesOnlyFIFOHead() async throws {
        let a = session(), b = session(12, pane: "b")
        let adapter = RecordingAdapter(route(a)), c = AgentCoordinator()
        await c.register(adapter, for: .codex)
        await c.ingest(.route(route(a))); await c.ingest(.route(route(b)))
        let p = prompt("a", session: a), q = prompt("b", session: b)
        await c.ingest(.prompt(p, kind: .codex)); await c.ingest(.prompt(q, kind: .codex))
        await #expect(throws: AgentRoutingError.notFIFOHead) { try await c.respond(id: q.id, revision: 1, response: .text("a")) }
        try await c.respond(id: p.id, revision: 1, response: .choice("original-id"))
        await adapter.setRoute(route(b))
        try await c.respond(id: q.id, revision: 1, response: .text("b"))
        #expect(await adapter.sent.map(\.sessionID) == [a, b])
    }
    @Test func reusedPIDChangedPaneAndOwnerRejectResponse() async {
        for changed in [session(birth: 2), session(pane: "different"), session(owner: "other")] {
            let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(route(changed))
            await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
            let p = prompt("p", session: id); await c.ingest(.prompt(p, kind: .codex))
            await #expect(throws: AgentRoutingError.identityChanged) { try await c.respond(id: p.id, revision: 1, response: .text("hello")) }
            #expect(await adapter.sent.isEmpty)
        }
    }
    @Test func revokedCapabilityPreventsSend() async {
        for changed in [route(session(), permission: false), route(session(), supported: false)] {
            let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(changed)
            await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
            let p = prompt("p", session: id); await c.ingest(.prompt(p, kind: .codex))
            await #expect(throws: AgentRoutingError.self) { try await c.respond(id: p.id, revision: 1, response: .text("hello")) }
            #expect(await adapter.sent.isEmpty)
        }
    }
    @Test func unknownReceiptNeverResends() async throws {
        let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(route(session()))
        await adapter.setReceipt(.unknown); await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
        let p = prompt("p", session: id); await c.ingest(.prompt(p, kind: .codex))
        try await c.respond(id: p.id, revision: 1, response: .text("hello"))
        await #expect(throws: AgentRoutingError.deliveryAlreadyAttempted) { try await c.respond(id: p.id, revision: 1, response: .text("hello")) }
        #expect(await c.receipts[p.id] == .unknown)
        #expect(await adapter.sent.count == 1)
        #expect(await c.queue.count == 1)
    }
    @Test func resolvedElsewhereAndInvalidChoiceCannotSend() async {
        let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(route(session()))
        await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
        let p = prompt("p", session: id); await c.ingest(.prompt(p, kind: .codex))
        await #expect(throws: AgentRoutingError.invalidResponse) { try await c.respond(id: p.id, revision: 1, response: .choice("guessed-allow")) }
        await c.ingest(.resolved(p.id, kind: .codex))
        await #expect(throws: AgentRoutingError.missingPrompt) { try await c.respond(id: p.id, revision: 1, response: .text("hello")) }
        #expect(await adapter.sent.isEmpty)
    }
}

extension AgentCoordinatorTests {
    @Test func resolutionAndRevisionDuringValidationPreventSend() async {
        for resolve in [true, false] {
            let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(route(session()))
            await adapter.hold(); await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
            let p = prompt("p", session: id); await c.ingest(.prompt(p, kind: .codex))
            let responseTask = Task { try await c.respond(id: p.id, revision: 1, response: .text("hello")) }
            while !(await adapter.validating) { await Task.yield() }
            if resolve { await c.ingest(.resolved(p.id, kind: .codex)) }
            else { await c.ingest(.prompt(prompt("p", session: id, revision: 2), kind: .codex)) }
            await adapter.release()
            await #expect(throws: AgentRoutingError.staleRevision) { try await responseTask.value }
            #expect(await adapter.sent.isEmpty)
        }
    }
}

extension AgentCoordinatorTests {
    @Test func collidingLocalIDsStayDistinctAndResolveIndependently() async {
        let a = session(), b = session(12, pane: "b"), c = AgentCoordinator()
        let first = prompt("same-local-id", session: a), second = prompt("same-local-id", session: b)
        await c.ingest(.prompt(first, kind: .codex))
        await c.ingest(.prompt(second, kind: .claudeCode))
        #expect(await c.queue.count == 2)
        await c.ingest(.resolved(second.id, kind: .codex))
        await c.ingest(.resolved(first.id, kind: .claudeCode))
        #expect(await c.queue.count == 2)
        await c.ingest(.resolved(second.id, kind: .claudeCode))
        #expect(await c.queue.head == first)
        await c.ingest(.prompt(second, kind: .claudeCode))
        #expect(await c.queue.count == 1)
    }
    @Test func rejectedOlderOtherKindCannotClaimPromptOwnership() async throws {
        let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(route(session()))
        await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
        let p = prompt("same", session: id, revision: 2)
        await c.ingest(.prompt(p, kind: .codex))
        await c.ingest(.prompt(prompt("same", session: id, revision: 1), kind: .claudeCode))
        await c.ingest(.prompt(prompt("same", session: id, revision: 99), kind: .claudeCode))
        await c.ingest(.prompt(prompt("other", session: id), kind: .claudeCode))
        #expect(await c.queue.count == 1)
        #expect(await c.queue.head == p)
        try await c.respond(id: p.id, revision: 2, response: .text("answer"))
        #expect(await adapter.sent == [p])
    }
}

extension AgentCoordinatorTests {
    @Test func permissionRevokedWhileValidationAwaitsPreventsSend() async {
        let id = session(), c = AgentCoordinator(), adapter = RecordingAdapter(route(session()))
        await adapter.hold(); await c.register(adapter, for: .codex); await c.ingest(.route(route(id)))
        let p = prompt("p", session: id); await c.ingest(.prompt(p, kind: .codex))
        let response = Task { try await c.respond(id: p.id, revision: 1, response: .text("hello")) }
        while !(await adapter.validating) { await Task.yield() }
        await c.ingest(.route(route(id, permission: false)))
        await adapter.release()
        await #expect(throws: AgentRoutingError.permissionRevoked) { try await response.value }
        #expect(await adapter.sent.isEmpty)
    }
    @Test func sameLocalIDAcrossKindsRoutesToExactAdapters() async throws {
        let a = session(), b = session(12, pane: "b"), c = AgentCoordinator()
        let codexRoute = route(a)
        let claudeRoute = AgentRoute(sessionID: b, kind: .claudeCode, capabilities: AgentCapabilities(readPrompt: true, sendResponse: true), permissionGranted: true)
        let codex = RecordingAdapter(codexRoute), claude = RecordingAdapter(claudeRoute)
        await c.register(codex, for: .codex); await c.register(claude, for: .claudeCode)
        await c.ingest(.route(codexRoute)); await c.ingest(.route(claudeRoute))
        let first = prompt("same", session: a), second = prompt("same", session: b)
        await c.ingest(.prompt(first, kind: .codex)); await c.ingest(.prompt(second, kind: .claudeCode))
        try await c.respond(id: first.id, revision: 1, response: .text("first"))
        #expect(await c.queue.head == second)
        try await c.respond(id: second.id, revision: 1, response: .text("second"))
        #expect(await codex.sent == [first]); #expect(await claude.sent == [second])
    }
}
