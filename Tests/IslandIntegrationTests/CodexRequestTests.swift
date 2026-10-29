import Foundation
import Testing
import IslandCore
@testable import IslandMac

struct CodexRequestTests {
    private let session = SessionID(ownerInstanceID: "codex-daemon:test", pid: 100, processStartTime: 1, terminalSessionKey: "thread")
    private func request(id: Any = 7, method: String = "item/commandExecution/requestApproval", extra: [String: Any] = [:]) throws -> Data {
        var params: [String: Any] = ["threadId": "thread", "turnId": "turn", "itemId": "item", "command": "pwd", "cwd": "/tmp", "reason": "Test approval"]
        params.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
    }
    @Test func multiplePreferencesRequireCompleteExactAnswers() throws {
        let questions: [[String: Any]] = [
            ["id": "layout", "question": "Which layout?", "options": [["label": "Compact"], ["label": "Wide"]]],
            ["id": "name", "question": "Project name?", "options": NSNull()]
        ]
        let pending = try #require(CodexPendingRequest.decode(request(method: "item/tool/requestUserInput", extra: ["questions": questions]), session: session))
        #expect(pending.prompt.questions.count == 2)
        #expect(!pending.prompt.accepts(answers: ["layout": "Compact"]))
        #expect(!pending.prompt.accepts(answers: ["layout": "Not offered", "name": "Island"]))
        let result = try JSONSerialization.jsonObject(with: pending.result(for: .answers(["layout": "Compact", "name": "Island"]))) as? [String: [String: [String: [String]]]]
        #expect(result == ["answers": ["layout": ["answers": ["Compact"]], "name": ["answers": ["Island"]]]])
    }
    @Test func commandReplyUsesOnlyAdvertisedScopes() throws {
        let pending = try #require(CodexPendingRequest.decode(request(extra: ["availableDecisions": ["accept", "acceptForSession", "decline"]]), session: session))
        #expect(pending.prompt.text.contains("pwd")); #expect(pending.prompt.text.contains("/tmp"))
        #expect(pending.prompt.choices.map(\.id) == ["accept", "acceptForSession", "decline"])
        let reply = try JSONSerialization.jsonObject(with: pending.result(for: .choice("accept"))) as? [String: String]
        #expect(reply == ["decision": "accept"])
        #expect(throws: AgentRoutingError.invalidResponse) { try pending.result(for: .choice("cancel")) }
    }
    @Test func livePwdApprovalKeepsAllThreeOptionsAndExactPolicyPayload() throws {
        let amendment: [String: Any] = ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": ["pwd"]]]
        let pending = try #require(CodexPendingRequest.decode(request(id: 2, extra: ["availableDecisions": ["accept", amendment, "cancel"], "proposedExecpolicyAmendment": ["pwd"]]), session: session))
        #expect(pending.prompt.choices.map(\.id) == ["accept", "execPolicy:1", "cancel"])
        #expect(pending.prompt.choices[1].text == "pwd")
        let result = try #require(JSONSerialization.jsonObject(with: pending.result(for: .choice("execPolicy:1"))) as? [String: [String: [String: [String]]]])
        #expect(result == ["decision": ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": ["pwd"]]]])
        #expect(throws: AgentRoutingError.invalidResponse) { try pending.result(for: .choice("acceptForSession")) }
    }
    @Test func sessionAndNetworkChoicesPreserveTheirAdvertisedScope() throws {
        for action in ["allow", "deny"] {
            let policy: [String: Any] = ["applyNetworkPolicyAmendment": ["network_policy_amendment": ["host": "example.test", "action": action]]]
            let pending = try #require(CodexPendingRequest.decode(request(extra: ["availableDecisions": ["acceptForSession", policy, "decline"]]), session: session))
            #expect(pending.prompt.choices.map(\.id) == ["acceptForSession", "networkPolicy:\(action):1", "decline"])
            let sessionReply = try JSONSerialization.jsonObject(with: pending.result(for: .choice("acceptForSession"))) as? [String: String]
            #expect(sessionReply == ["decision": "acceptForSession"])
            let result = try JSONSerialization.jsonObject(with: pending.result(for: .choice("networkPolicy:\(action):1"))) as? [String: [String: [String: [String: String]]]]
            #expect(result == ["decision": ["applyNetworkPolicyAmendment": ["network_policy_amendment": ["host": "example.test", "action": action]]]])
        }
    }
    @Test func malformedPolicyAndDecisionListsCannotInventAnApproval() throws {
        let malformed: [String: Any] = ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": ["pwd"], "extra": "hidden"]]
        #expect(CodexPendingRequest.decode(try request(extra: ["availableDecisions": [malformed]]), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(extra: ["availableDecisions": "accept"]), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(extra: ["availableDecisions": ["accept", "accept"]]), session: session) == nil)
    }
    @Test func requestIDsAndThreadsRemainIsolated() throws {
        let numeric = try #require(CodexPendingRequest.decode(request(id: 7), session: session))
        let string = try #require(CodexPendingRequest.decode(request(id: "7"), session: session))
        #expect(numeric.prompt.id != string.prompt.id)
        #expect(CodexPendingRequest.decode(try request(extra: ["threadId": "other"]), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(id: true), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(id: 1.5), session: session) == nil)
    }
    @Test func unsupportedOrIncompleteRequestsHaveNoActions() throws {
        #expect(CodexPendingRequest.decode(try request(method: "mcpServer/elicitation/request"), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(extra: ["command": NSNull()]), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(extra: ["availableDecisions": ["unknown-decision"]]), session: session) == nil)
    }
    @Test func singleUserQuestionPreservesOptionLabelAndQuestionID() throws {
        let question: [String: Any] = ["id": "q", "header": "Choose", "question": "Which option?", "options": [["label": "A", "description": "First"], ["label": "B", "description": "Second"]]]
        let pending = try #require(CodexPendingRequest.decode(request(method: "item/tool/requestUserInput", extra: ["questions": [question], "isBlocking": true]), session: session))
        let reply = try JSONSerialization.jsonObject(with: pending.result(for: .choice("answer:1"))) as? [String: [String: [String: [String]]]]
        #expect(reply == ["answers": ["q": ["answers": ["B"]]]])
        #expect(!pending.prompt.acceptsText)
        var secret = question; secret["isSecret"] = true
        #expect(CodexPendingRequest.decode(try request(method: "item/tool/requestUserInput", extra: ["questions": [secret]]), session: session) == nil)
        #expect(CodexPendingRequest.decode(try request(method: "item/tool/requestUserInput", extra: ["questions": [question, question]]), session: session) == nil)
    }
}

struct CodexLiveTransportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_CODEX_LIVE"] == "1", "Requires an already-running shared daemon"))
    func readsLoadedMetadataWithoutJoiningOrAnswering() async throws {
        let socket = CodexSocket()
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/app-server-control/app-server-control.sock").resolvingSymlinksInPath()
        try await socket.connect(path: path)
        do {
            let params = try JSONSerialization.data(withJSONObject: ["clientInfo": ["name": "island-mac-transport-check", "version": "0.2.0"]])
            _ = try await socket.call("initialize", params: params)
            try await socket.notify("initialized")
            let data = try await socket.call("thread/loaded/list", params: Data("{\"limit\":100}".utf8))
            let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(result["data"] is [String])
            print("Live Codex WebSocket: loaded thread count=\((result["data"] as? [String])?.count ?? 0); no subscriptions or replies")
            await socket.close()
        } catch { await socket.close(); throw error }
    }
}

struct CodexQueueUpdateTests {
    @Test func newAndResolvedRequestsPublishWithoutDiscoveryPolling() async {
        let coordinator = AgentCoordinator()
        let session = SessionID(ownerInstanceID: "codex-daemon:test", pid: 100, processStartTime: 1, terminalSessionKey: "thread")
        let prompt = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "request"), revision: 1, text: "A real protocol request would enter here", choices: [], acceptsText: true)
        var iterator = coordinator.updates.makeAsyncIterator()
        await coordinator.ingest(.prompt(prompt, kind: .codex))
        #expect(await iterator.next()?.head == prompt)
        await coordinator.ingest(.resolved(prompt.id, kind: .codex))
        #expect(await iterator.next()?.count == 0)
    }
}
