public actor AgentCoordinator {
    public private(set) var queue = PromptQueue()
    public private(set) var receipts: [PromptID: ResponseReceipt] = [:]
    private var routes: [SessionID: AgentRoute] = [:]
    private var kinds: [PromptID: AgentKind] = [:]
    private var adapters: [AgentKind: any AgentAdapter] = [:]
    private var attempted: Set<PromptID> = []
    private var streams: [AgentKind: Task<Void, Never>] = [:]
    public init() {}
    public func register(_ adapter: any AgentAdapter, for kind: AgentKind) {
        streams[kind]?.cancel()
        adapters[kind] = adapter
        streams[kind] = Task { [weak self] in
            for await event in adapter.events() {
                guard !Task.isCancelled else { return }
                await self?.ingest(event)
            }
        }
    }
    public func stop() { for task in streams.values { task.cancel() }; streams.removeAll() }
    public func ingest(_ event: AgentEvent) {
        switch event {
        case .route(let route): routes[route.sessionID] = route
        case let .prompt(prompt, kind): queue.receive(prompt); kinds[prompt.id] = kind
        case .resolved(let id): queue.resolve(id)
        case .exited(let id): routes.removeValue(forKey: id); queue.sessionExited(id)
        }
    }
    public func respond(id: PromptID, revision: UInt64, response: AgentResponse) async throws {
        guard let prompt = queue.prompt(id) else { throw AgentRoutingError.missingPrompt }
        guard queue.head?.id == id else { throw AgentRoutingError.notFIFOHead }
        guard prompt.revision == revision else { throw AgentRoutingError.staleRevision }
        switch response {
        case .choice(let choice): guard prompt.choices.contains(where: { $0.id == choice }) else { throw AgentRoutingError.invalidResponse }
        case .text: guard prompt.acceptsText else { throw AgentRoutingError.invalidResponse }
        }
        guard !attempted.contains(id) else { throw AgentRoutingError.deliveryAlreadyAttempted }
        guard let kind = kinds[id], let adapter = adapters[kind], let route = routes[prompt.sessionID] else { throw AgentRoutingError.unavailable }
        try check(route, prompt: prompt, kind: kind)
        let fresh = try await adapter.validate(sessionID: prompt.sessionID)
        // Actor reentrancy: a resolution, revocation or new revision may arrive during validation.
        guard queue.prompt(id) == prompt, queue.head?.id == id else { throw AgentRoutingError.staleRevision }
        guard let current = routes[prompt.sessionID] else { throw AgentRoutingError.identityChanged }
        try check(current, prompt: prompt, kind: kind)
        try check(fresh, prompt: prompt, kind: kind)
        guard !attempted.contains(id) else { throw AgentRoutingError.deliveryAlreadyAttempted }
        attempted.insert(id)
        receipts[id] = .unknown
        do {
            let receipt = try await adapter.respond(prompt: prompt, response: response)
            receipts[id] = receipt
            if receipt == .confirmed { queue.resolve(id) }
        } catch { throw error } // An exception after sending has unknown delivery; never auto retry.
    }
    private func check(_ route: AgentRoute, prompt: AgentPrompt, kind: AgentKind) throws {
        guard route.sessionID == prompt.sessionID, route.kind == kind else { throw AgentRoutingError.identityChanged }
        guard route.permissionGranted else { throw AgentRoutingError.permissionRevoked }
        guard route.capabilities.readPrompt, route.capabilities.sendResponse else { throw AgentRoutingError.unavailable }
    }
}
