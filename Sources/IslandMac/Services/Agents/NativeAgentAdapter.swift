import Combine
import Foundation
import IslandCore

/// Shared fail-closed adapter for all four executable strategies. Phase 1 verified no read/send mechanism.
struct NativeAgentAdapter: AgentAdapter {
    let kind: AgentKind
    func events() -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    func validate(sessionID: SessionID) async throws -> AgentRoute { throw AgentRoutingError.unavailable }
    func respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt { throw AgentRoutingError.unavailable }
    func openOrigin(sessionID: SessionID) async throws { throw AgentRoutingError.unavailable }
}

@MainActor final class AgentRegistry: ObservableObject {
    @Published private(set) var agents: [DiscoveredAgent] = []
    @Published private(set) var unmappedCount = 0
    @Published private(set) var prompt: AgentPrompt?
    @Published private(set) var pendingCount = 0
    @Published var responseError: String?
    let coordinator = AgentCoordinator()
    private var task: Task<Void, Never>?
    func start(terminals: TerminalSessionStore, changed: @escaping (Int) -> Void) {
        guard task == nil else { return }
        task = Task { [weak self, weak terminals] in
            guard let self else { return }
            for kind in AgentKind.allCases { await coordinator.register(NativeAgentAdapter(kind: kind), for: kind) }
            while !Task.isCancelled {
                guard let terminals else { return }
                let owned = terminals.sessionIDs.filter { terminals.isRunning($0) }
                let found = await Task.detached { HostSessionDiscovery.discover(records: HostSessionDiscovery.snapshot(), owned: owned) }.value
                agents = found.filter { $0.ownedTerminal != nil || $0.reason == "externalPaneUnknown" }
                unmappedCount = found.count - agents.count
                let queue = await coordinator.queue
                if prompt?.id != queue.head?.id { responseError = nil }
                prompt = queue.head; pendingCount = queue.count; changed(queue.count)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    func respond(_ response: AgentResponse, to prompt: AgentPrompt) {
        Task {
            do {
                try await coordinator.respond(id: prompt.id, revision: prompt.revision, response: response)
                switch await coordinator.receipts[prompt.id] {
                case .unknown: responseError = "deliveryUnknown"
                case .sent: responseError = "deliverySent"
                case .rejected: responseError = "deliveryRejected"
                default: responseError = nil
                }
            }
            catch { responseError = "responseUnavailable" }
            let queue = await coordinator.queue
            self.prompt = queue.head; pendingCount = queue.count
        }
    }
    func stop() { task?.cancel(); task = nil; Task { await coordinator.stop() } }
}
