import Foundation
import CoreFoundation
import IslandCore

struct CodexPendingRequest: Sendable {
    enum Reply: Sendable { case decision([String: Data]), question(String, [String: String]), questions }
    let rawID: Data
    let prompt: AgentPrompt
    let reply: Reply

    static func decode(_ data: Data, session: SessionID, origin: String? = nil) -> Self? {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = message["method"] as? String,
              let id = message["id"], let rawID = requestID(id),
              let params = message["params"] as? [String: Any],
              params["threadId"] as? String == session.terminalSessionKey,
              let turn = params["turnId"] as? String, !turn.isEmpty,
              let item = params["itemId"] as? String, !item.isEmpty else { return nil }
        let promptID = PromptID(sessionID: session, localRequestID: rawID.base64EncodedString())
        if method == "item/commandExecution/requestApproval" {
            guard let command = params["command"] as? String, !command.isEmpty,
                  let cwd = params["cwd"] as? String, cwd.hasPrefix("/") else { return nil }
            if let raw = params["availableDecisions"], !(raw is NSNull), !(raw is [Any]) { return nil }
            let decisions = params["availableDecisions"] as? [Any] ?? ["accept", "decline", "cancel"]
            var choices: [PromptChoice] = []
            var replies: [String: Data] = [:]
            for (index, decision) in decisions.enumerated() {
                guard let (choice, payload) = approvalChoice(decision, index: index) else { continue }
                guard replies[choice.id] == nil else { return nil }
                choices.append(choice); replies[choice.id] = payload
            }
            guard !choices.isEmpty else { return nil }
            var details = [params["reason"] as? String, command, cwd].compactMap { $0 }
            if let environment = params["environmentId"] as? String { details.append("Environment: " + environment) }
            for key in ["additionalPermissions", "networkApprovalContext"] {
                if let object = params[key] as? [String: Any], !object.isEmpty,
                   let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { details.append(text) }
            }
            return Self(rawID: rawID, prompt: AgentPrompt(id: promptID, revision: 1, text: details.joined(separator: "\n\n"), choices: choices, acceptsText: false, sourceLabel: origin), reply: .decision(replies))
        }
        if method == "item/tool/requestUserInput" {
            if let questions = params["questions"] as? [[String: Any]], questions.count > 1 {
                guard questions.count <= 3 else { return nil }
                var groups: [AgentQuestion] = []
                for question in questions {
                    guard question["isSecret"] as? Bool != true,
                          let id = question["id"] as? String, !id.isEmpty,
                          !groups.contains(where: { $0.id == id }),
                          let text = question["question"] as? String, !text.isEmpty else { return nil }
                    if let raw = question["options"], !(raw is NSNull), !(raw is [[String: Any]]) { return nil }
                    let options = question["options"] as? [[String: Any]] ?? []
                    var choices: [PromptChoice] = []
                    for option in options {
                        guard let label = option["label"] as? String, !label.isEmpty,
                              !choices.contains(where: { $0.id == label }) else { return nil }
                        choices.append(PromptChoice(id: label, text: [label, option["description"] as? String].compactMap { $0 }.joined(separator: " — ")))
                    }
                    groups.append(AgentQuestion(id: id, text: text, choices: choices, acceptsText: choices.isEmpty || question["isOther"] as? Bool == true))
                }
                return Self(rawID: rawID, prompt: AgentPrompt(id: promptID, revision: 1, text: "", choices: [], acceptsText: false, sourceLabel: origin, questions: groups), reply: .questions)
            }
            guard let questions = params["questions"] as? [[String: Any]], questions.count == 1,
                  let question = questions.first, question["isSecret"] as? Bool != true,
                  let questionID = question["id"] as? String, !questionID.isEmpty,
                  let text = question["question"] as? String, !text.isEmpty else { return nil }
            let options = question["options"] as? [[String: Any]] ?? []
            var labels: [String: String] = [:]
            var choices: [PromptChoice] = []
            for (index, option) in options.enumerated() {
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                let key = "answer:\(index)"; labels[key] = label
                let description = option["description"] as? String
                choices.append(PromptChoice(id: key, text: [label, description].compactMap { $0 }.joined(separator: " — ")))
            }
            return Self(rawID: rawID, prompt: AgentPrompt(id: promptID, revision: 1, text: text, choices: choices, acceptsText: options.isEmpty || question["isOther"] as? Bool == true, sourceLabel: origin), reply: .question(questionID, labels))
        }
        return nil
    }
    private static func approvalChoice(_ decision: Any, index: Int) -> (PromptChoice, Data)? {
        let choice: PromptChoice
        if let name = decision as? String {
            let labels = ["accept": "Allow once", "acceptForSession": "Allow for this session", "decline": "Deny", "cancel": "Cancel turn"]
            guard let label = labels[name] else { return nil }
            choice = PromptChoice(id: name, text: label)
        } else if let object = decision as? [String: Any], object.count == 1,
                  let amendment = object["acceptWithExecpolicyAmendment"] as? [String: Any], amendment.count == 1,
                  let prefix = amendment["execpolicy_amendment"] as? [String], !prefix.isEmpty {
            let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=+@%-")
            let label = prefix.map { token in
                !token.isEmpty && token.unicodeScalars.allSatisfy(safe.contains) ? token : "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }.joined(separator: " ")
            choice = PromptChoice(id: "execPolicy:\(index)", text: label)
        } else if let object = decision as? [String: Any], object.count == 1,
                  let amendment = object["applyNetworkPolicyAmendment"] as? [String: Any], amendment.count == 1,
                  let policy = amendment["network_policy_amendment"] as? [String: Any], policy.count == 2,
                  let action = policy["action"] as? String, ["allow", "deny"].contains(action),
                  let host = policy["host"] as? String, !host.isEmpty {
            choice = PromptChoice(id: "networkPolicy:\(action):\(index)", text: host)
        } else { return nil }
        guard let payload = try? JSONSerialization.data(withJSONObject: decision, options: [.fragmentsAllowed, .sortedKeys]) else { return nil }
        return (choice, payload)
    }
    static func requestID(_ value: Any) -> Data? {
        guard value is String || (value is NSNumber && CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID()),
              let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return nil }
        if let number = value as? NSNumber, ["f", "d"].contains(String(cString: number.objCType)) { return nil }
        return data
    }
    func result(for response: AgentResponse) throws -> Data {
        let value: [String: Any]
        switch (reply, response) {
        case (.decision(let replies), .choice(let decision)):
            guard let payload = replies[decision] else { throw AgentRoutingError.invalidResponse }
            value = ["decision": try JSONSerialization.jsonObject(with: payload, options: .fragmentsAllowed)]
        case (.question(let id, let labels), .choice(let key)):
            guard let label = labels[key] else { throw AgentRoutingError.invalidResponse }
            value = ["answers": [id: ["answers": [label]]]]
        case (.question(let id, _), .text(let text)):
            guard prompt.acceptsText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentRoutingError.invalidResponse }
            value = ["answers": [id: ["answers": [text]]]]
        case (.questions, .answers(let answers)):
            guard prompt.accepts(answers: answers) else { throw AgentRoutingError.invalidResponse }
            value = ["answers": answers.mapValues { ["answers": [$0]] }]
        default: throw AgentRoutingError.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: value)
    }
}

actor CodexAdapter: AgentAdapter {
    nonisolated private let stream: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    private var socket: CodexSocket?
    private var receiver: Task<Void, Never>?
    private var connectionID = UUID().uuidString
    private var daemon: HostSessionDiscovery.ProcessRecord?
    private var sessions: [String: SessionID] = [:]
    private var origins: [String: String] = [:]
    private var verified = Set<String>()
    private var early: [String: [Data]] = [:]
    private var pending: [PromptID: CodexPendingRequest] = [:]
    private var submitted = Set<PromptID>()
    private var resolved = Set<PromptID>()
    private var refreshing = false
    private let hookMailbox = CodexHookMailbox()
    private var hookPending: [PromptID: CodexHookPending] = [:]
    init() {
        let (stream, continuation) = AsyncStream<AgentEvent>.makeStream()
        self.stream = stream; self.continuation = continuation
    }
    nonisolated func events() -> AsyncStream<AgentEvent> { stream }
    var isConnected: Bool { socket != nil && daemon != nil }
    var monitoredAgents: [DiscoveredAgent] {
        sessions.keys.sorted().compactMap { id in
            guard verified.contains(id), let session = sessions[id] else { return nil }
            return DiscoveredAgent(pid: session.pid, birth: session.processStartTime, kind: .codex,
                                   host: nil, sessionID: session, ownedTerminal: nil,
                                   reason: "codexMonitoring", sourceLabel: origins[id])
        }
    }
    static func sharedDaemon(in records: [HostSessionDiscovery.ProcessRecord], home: URL) -> HostSessionDiscovery.ProcessRecord? {
        records.first {
            $0.uid == getuid() && $0.parent == 1 &&
            $0.executable.hasPrefix(home.appendingPathComponent("packages/app-server-daemon").path + "/") &&
            URL(fileURLWithPath: $0.executable).lastPathComponent == "codex"
        }
    }
    private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentRoutingError.unavailable }
        return value
    }
    private func loaded(_ socket: CodexSocket) async throws -> Set<String> {
        var result = Set<String>(); var cursor: String?
        repeat {
            var params: [String: Any] = ["limit": 100]
            if let cursor { params["cursor"] = cursor }
            let page = try object(await socket.call("thread/loaded/list", params: json(params)))
            guard let ids = page["data"] as? [String], result.count + ids.count <= 500 else { throw AgentRoutingError.unavailable }
            result.formUnion(ids); cursor = page["nextCursor"] as? String
        } while cursor != nil
        return result
    }
    private func refreshHooks(records: [HostSessionDiscovery.ProcessRecord]) {
        do {
            try hookMailbox.prepare()
            if let birth = CodexHookMailbox.birth(getpid()) {
                let temp = hookMailbox.root.appendingPathComponent(UUID().uuidString + ".host")
                try hookMailbox.write(JSONEncoder().encode(CodexHookHost(pid: getpid(), birth: birth)), to: temp)
                guard rename(temp.path, hookMailbox.root.appendingPathComponent("host.json").path) == 0 else {
                    try? FileManager.default.removeItem(at: temp); return
                }
            }
            for (id, request) in hookPending where !request.isLive(mailbox: hookMailbox, records: records) {
                hookPending.removeValue(forKey: id)
                continuation.yield(.exited(request.prompt.sessionID))
            }
            let helper = hookMailbox.root.deletingLastPathComponent().appendingPathComponent("IslandHook").path
            let directories = try FileManager.default.contentsOfDirectory(at: hookMailbox.root, includingPropertiesForKeys: nil)
            for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil && hookMailbox.secureDirectory(directory) {
                guard let data = hookMailbox.read(directory.appendingPathComponent("request.json")),
                      let envelope = try? JSONDecoder().decode(CodexHookEnvelope.self, from: data),
                      envelope.id.uuidString == directory.lastPathComponent else { continue }
                if Date().timeIntervalSince(envelope.createdAt) > 130 && CodexHookMailbox.birth(envelope.pid) != envelope.birth {
                    try? FileManager.default.removeItem(at: directory)
                    continue
                }
                guard let request = CodexHookPending.decode(envelope, records: records, helperPath: helper),
                      hookPending[request.prompt.id] == nil else { continue }
                hookPending[request.prompt.id] = request
                continuation.yield(.route(hookRoute(request)))
                continuation.yield(.prompt(request.prompt, kind: .codex))
            }
        } catch { /* An unavailable bridge leaves the original Codex flow untouched. */ }
    }
    private func hookRoute(_ request: CodexHookPending) -> AgentRoute {
        AgentRoute(sessionID: request.prompt.sessionID, kind: .codex,
                   capabilities: AgentCapabilities(discovery: true, readPrompt: true, sendResponse: true), permissionGranted: true)
    }
    func refresh(records: [HostSessionDiscovery.ProcessRecord]) async {
        refreshHooks(records: records)
        guard !refreshing else { return }; refreshing = true
        defer { refreshing = false }
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let owner = Self.sharedDaemon(in: records, home: home) else { await disconnect(); return }
        if let daemon, daemon.pid != owner.pid || daemon.birth != owner.birth { await disconnect() }
        do {
            if socket == nil {
                let path = home.appendingPathComponent("app-server-control/app-server-control.sock").resolvingSymlinksInPath()
                let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                guard attributes[.type] as? FileAttributeType == .typeSocket,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0 else { return }
                let client = CodexSocket(); socket = client; daemon = owner
                let token = connectionID
                try await client.connect(path: path)
                // Do not subscribe to transcript, reasoning, command output, or file patches.
                let suppressed = ["thread/started", "turn/started", "turn/completed", "turn/diff/updated", "turn/plan/updated", "item/started", "item/completed", "item/agentMessage/delta", "item/plan/delta", "item/commandExecution/outputDelta", "item/commandExecution/terminalInteraction", "item/fileChange/outputDelta", "item/fileChange/patchUpdated", "item/reasoning/summaryTextDelta", "item/reasoning/summaryPartAdded", "item/reasoning/textDelta", "command/exec/outputDelta", "process/outputDelta", "item/mcpToolCall/progress", "mcpServer/event/stream/notification"]
                _ = try await client.call("initialize", params: json(["clientInfo": ["name": "island-mac", "version": "0.2.0"], "capabilities": ["experimentalApi": true, "optOutNotificationMethods": suppressed]]))
                // initialize completion is sufficient for app-server readiness; initialized is a notification.
                try await client.notify("initialized")
                guard token == connectionID else { return }
                receiver = Task { [weak self] in
                    for await data in client.messages { await self?.receive(data, token: token) }
                    await self?.connectionEnded(token: token)
                }
            }
            guard let client = socket, let daemon else { return }
            let token = connectionID
            let ids = try await loaded(client)
            guard token == connectionID else { return }
            for id in Array(sessions.keys) where !ids.contains(id) { remove(id) }
            for id in ids {
                let response = try object(await client.call("thread/read", params: json(["threadId": id, "includeTurns": false])))
                guard token == connectionID else { return }
                guard let thread = response["thread"] as? [String: Any], let status = thread["status"] as? [String: Any] else { continue }
                guard status["type"] as? String == "active" else {
                    if sessions[id] != nil { _ = try? await client.call("thread/unsubscribe", params: json(["threadId": id])); remove(id) }
                    continue
                }
                guard sessions[id] == nil else { continue }
                // A running-only resume is not atomic in this protocol; recheck before and after joining.
                guard try await loaded(client).contains(id), token == connectionID else { continue }
                let session = SessionID(ownerInstanceID: "codex-daemon:\(token):\(UUID().uuidString)", pid: daemon.pid, processStartTime: daemon.birth, terminalSessionKey: id)
                sessions[id] = session
                origins[id] = [(thread["name"] as? String ?? "Codex") + " · " + String(id.prefix(8)), thread["cwd"] as? String].compactMap { $0 }.joined(separator: "\n")
                let resumed = try object(await client.call("thread/resume", params: json(["threadId": id, "excludeTurns": true])))
                guard token == connectionID else { return }
                let resumedThread = resumed["thread"] as? [String: Any]
                let resumedStatus = resumedThread?["status"] as? [String: Any]
                guard resumedStatus?["type"] as? String == "active", try await loaded(client).contains(id) else {
                    _ = try? await client.call("thread/unsubscribe", params: json(["threadId": id])); remove(id); continue
                }
                verified.insert(id)
                continuation.yield(.route(route(session)))
                for data in early.removeValue(forKey: id) ?? [] { receive(data, token: token) }
            }
        } catch { await disconnect() }
    }
    private func route(_ id: SessionID) -> AgentRoute {
        AgentRoute(sessionID: id, kind: .codex, capabilities: AgentCapabilities(discovery: true, readPrompt: true, sendResponse: true), permissionGranted: true)
    }
    func validate(sessionID: SessionID) async throws -> AgentRoute {
        if sessionID.ownerInstanceID.hasPrefix("codex-hook:") {
            guard let request = hookPending.values.first(where: { $0.prompt.sessionID == sessionID }),
                  request.isLive(mailbox: hookMailbox) else { throw AgentRoutingError.identityChanged }
            return hookRoute(request)
        }
        guard let client = socket, verified.contains(sessionID.terminalSessionKey), sessions[sessionID.terminalSessionKey] == sessionID else { throw AgentRoutingError.unavailable }
        let token = connectionID
        let live = HostSessionDiscovery.snapshot().contains { $0.pid == sessionID.pid && $0.birth == sessionID.processStartTime && $0.uid == getuid() }
        guard live, try await loaded(client).contains(sessionID.terminalSessionKey), token == connectionID,
              sessions[sessionID.terminalSessionKey] == sessionID else { throw AgentRoutingError.identityChanged }
        return route(sessionID)
    }
    func respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt {
        if let request = hookPending[prompt.id] {
            guard request.prompt == prompt, request.isLive(mailbox: hookMailbox),
                  case .choice(let choice) = response, prompt.choices.contains(where: { $0.id == choice }) else { throw AgentRoutingError.invalidResponse }
            _ = try CodexHookMailbox.decision(event: request.event, choice: choice)
            try hookMailbox.write(Data(choice.utf8), to: hookMailbox.directory(request.envelope.id).appendingPathComponent("response.json"))
            return .sent
        }
        guard let request = pending[prompt.id], request.prompt == prompt, let client = socket,
              verified.contains(prompt.sessionID.terminalSessionKey), !submitted.contains(prompt.id) else { throw AgentRoutingError.unavailable }
        let result = try request.result(for: response)
        submitted.insert(prompt.id)
        try await client.respond(id: request.rawID, result: result)
        return .sent // Only serverRequest/resolved removes the request; a write is not confirmation.
    }
    func readChat(session: SessionID) async throws -> [AgentChatEntry] {
        guard let client = socket, daemon != nil, UUID(uuidString: session.terminalSessionKey) != nil else { throw AgentRoutingError.unavailable }
        let live = HostSessionDiscovery.snapshot().contains {
            $0.uid == getuid() && $0.pid == session.pid && $0.birth == session.processStartTime &&
            HostSessionDiscovery.kind(for: $0.executable) == .codex
        }
        guard live else { throw AgentRoutingError.identityChanged }
        let id = session.terminalSessionKey
        let metadata = try object(await client.call("thread/read", params: json(["threadId": id, "includeTurns": false])))
        guard let thread = metadata["thread"] as? [String: Any] else { throw AgentRoutingError.unavailable }
        if thread["historyMode"] as? String == "paginated" {
            var turns: [[String: Any]] = []
            var cursor: String?
            var seen = Set<String>()
            repeat {
                var params: [String: Any] = ["threadId": id, "itemsView": "full", "sortDirection": "asc", "limit": 100]
                if let cursor { params["cursor"] = cursor }
                let page = try object(await client.call("thread/turns/list", params: json(params)))
                guard let data = page["data"] as? [[String: Any]] else { throw AgentRoutingError.unavailable }
                turns.append(contentsOf: data)
                cursor = page["nextCursor"] as? String
                if let cursor, !seen.insert(cursor).inserted { throw AgentRoutingError.unavailable }
            } while cursor != nil
            return try AgentChatEntry.parse(json(["thread": ["turns": turns]]))
        }
        let data = try await client.call("thread/read", params: json(["threadId": id, "includeTurns": true]))
        return try AgentChatEntry.parse(data)
    }
    func queueChat(_ message: CodexChatMessage) async throws -> Data {
        let parameters = try message.parameters()
        guard let client = socket, daemon != nil else { throw AgentRoutingError.unavailable }
        let session = message.session
        let live = HostSessionDiscovery.snapshot().contains {
            $0.uid == getuid() && $0.pid == session.pid && $0.birth == session.processStartTime &&
            HostSessionDiscovery.kind(for: $0.executable) == .codex
        }
        guard live else { throw AgentRoutingError.identityChanged }
        // Queue on the existing thread; never resume it on a second server or start/fork a thread.
        return try await client.call("thread/queue/add", params: parameters)
    }
    func openOrigin(sessionID: SessionID) async throws { throw AgentRoutingError.unavailable }
    private func receive(_ data: Data, token: String) {
        guard token == connectionID, let value = try? object(data), let method = value["method"] as? String,
              let params = value["params"] as? [String: Any], let id = params["threadId"] as? String,
              let session = sessions[id] else { return }
        if method == "serverRequest/resolved", let raw = params["requestId"], let rawID = CodexPendingRequest.requestID(raw) {
            let promptID = PromptID(sessionID: session, localRequestID: rawID.base64EncodedString())
            pending.removeValue(forKey: promptID)
            resolved.insert(promptID)
            continuation.yield(.resolved(promptID, kind: .codex))
            return
        }
        if method == "thread/closed" { remove(id); return }
        guard value["id"] != nil else { return }
        guard verified.contains(id) else {
            if (early[id]?.count ?? 0) < 32 { early[id, default: []].append(data) }
            return
        }
        guard let request = CodexPendingRequest.decode(data, session: session, origin: origins[id]), pending[request.prompt.id] == nil,
              !resolved.contains(request.prompt.id) else { return }
        pending[request.prompt.id] = request
        continuation.yield(.prompt(request.prompt, kind: .codex))
    }
    private func remove(_ id: String) {
        if let session = sessions.removeValue(forKey: id) {
            pending = pending.filter { $0.key.sessionID != session }
            submitted = submitted.filter { $0.sessionID != session }
            resolved = resolved.filter { $0.sessionID != session }
            continuation.yield(.exited(session))
        }
        early.removeValue(forKey: id); verified.remove(id)
        origins.removeValue(forKey: id)
    }
    private func connectionEnded(token: String) async { if token == connectionID { await disconnect() } }
    func disconnect() async {
        connectionID = UUID().uuidString
        receiver?.cancel(); receiver = nil
        for id in Array(sessions.keys) { remove(id) }
        let client = socket; socket = nil; daemon = nil
        await client?.close()
    }
}
