import Combine
import Foundation
import IslandCore

/// Unsupported agents remain unavailable until their native protocol is implemented.
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
    @Published private(set) var submitting: PromptID?
    @Published private(set) var submitted = Set<PromptID>()
    @Published private(set) var codexConnected = false
    @Published private(set) var completion: DiscoveredAgent?
    @Published var selectedAgentID: String?
    var completionChanged: (() -> Void)?
    private var completions = AgentCompletionTracker()
    private let codex = CodexAdapter()
    private var chatDrafts: [SessionID: AgentChatDraft] = [:]
    let coordinator: AgentCoordinator
    private var pendingDidChange: ((Int) -> Void)?
    init(coordinator: AgentCoordinator = AgentCoordinator(), pendingChanged: ((Int) -> Void)? = nil) {
        self.coordinator = coordinator; self.pendingDidChange = pendingChanged
    }
    private var task: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    func start(terminals: TerminalSessionStore, changed: @escaping (Int) -> Void) {
        guard task == nil else { return }
        pendingDidChange = changed
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await queue in coordinator.updates {
                guard !Task.isCancelled else { return }
                if prompt?.id != queue.head?.id { responseError = nil }
                publish(queue)
            }
        }
        task = Task { [weak self, weak terminals] in
            guard let self else { return }
            await coordinator.register(codex, for: .codex)
            for kind in AgentKind.allCases where kind != .codex { await coordinator.register(NativeAgentAdapter(kind: kind), for: kind) }
            while !Task.isCancelled {
                guard let terminals else { return }
                let owned = terminals.sessionIDs.filter { terminals.isRunning($0) }
                let records = await Task.detached { HostSessionDiscovery.snapshot() }.value
                let found = HostSessionDiscovery.discover(records: records, owned: owned)
                let observed = await Task.detached { CodexSessionObserver.scan(records: records) }.value
                let local = found.filter { $0.ownedTerminal != nil || $0.host != nil }
                unmappedCount = found.count - local.count
                await codex.refresh(records: records)
                codexConnected = await codex.isConnected
                let monitored = await codex.monitoredAgents
                let monitoredIDs = Set(monitored.compactMap { $0.sessionID?.terminalSessionKey })
                let observedPIDs = Set(observed.map(\.pid))
                agents = local.filter { !observedPIDs.contains($0.pid) && $0.host != .codexDesktop } + observed.filter { !monitoredIDs.contains($0.sessionID?.terminalSessionKey ?? "") } + monitored
                if let finished = completions.update(agents).max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) {
                    completion = finished
                    completionChanged?()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    func chatDraft(for session: SessionID) -> AgentChatDraft {
        if let draft = chatDrafts[session] { return draft }
        let draft = AgentChatDraft(); chatDrafts[session] = draft
        return draft
    }
    func readChat(for session: SessionID) async throws -> [AgentChatEntry] {
        guard agents.contains(where: { $0.sessionID == session && $0.kind == .codex }) else { throw AgentRoutingError.unavailable }
        if session.ownerInstanceID == "codex-observed" {
            return try await Task.detached { try CodexSessionObserver.readChat(session: session) }.value
        }
        return try await codex.readChat(session: session)
    }
    func sendChat(to session: SessionID) {
        let draft = chatDraft(for: session)
        guard agents.contains(where: { $0.sessionID == session && $0.kind == .codex }) else {
            draft.status = "chatUnavailable"; return
        }
        guard let message = draft.begin(for: session) else { return }
        Task {
            defer { draft.sending = false }
            do {
                let response = try await codex.queueChat(message)
                guard message.acknowledged(by: response) else {
                    draft.uncertain = true; draft.status = "chatUnknown"; return
                }
                if draft.text == message.text { draft.text = "" }
                draft.status = "chatQueued"
            } catch let error as AgentRoutingError {
                draft.status = error == .identityChanged ? "chatSessionChanged" : "chatUnavailable"
            } catch CodexSocket.Failure.rpcRejected {
                draft.status = "chatRejected"
            } catch {
                // A dropped response cannot prove that the queue write failed; never retry automatically.
                draft.uncertain = true; draft.status = "chatUnknown"
            }
        }
    }
    func respond(_ response: AgentResponse, to prompt: AgentPrompt) -> Task<Void, Never> {
        guard submitting == nil, !submitted.contains(prompt.id) else { return Task {} }
        submitting = prompt.id
        submitted.insert(prompt.id)
        return Task {
            defer { submitting = nil }
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
            if updatesTask == nil { publish(await coordinator.queue) }
            if self.prompt?.id != prompt.id { responseError = nil }
        }
    }
    private func publish(_ queue: PromptQueue) {
        submitted = submitted.filter { queue.prompt($0) != nil }
        prompt = queue.head; pendingCount = queue.count
        pendingDidChange?(queue.count)
    }
    func stop() {
        task?.cancel(); task = nil; updatesTask?.cancel(); updatesTask = nil
        Task { await codex.disconnect(); await coordinator.stop() }
    }
}
