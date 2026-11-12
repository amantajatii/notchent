import AppKit
import Foundation
import Testing
import IslandCore
@testable import IslandMac

struct CodexChatMessageTests {
    private let session = SessionID(ownerInstanceID: "codex-observed", pid: 100, processStartTime: 1, terminalSessionKey: "01a17228-62b4-7de3-8486-b52b4bd9f8cf")
    @Test func historyKeepsMessagesInOrderAndExcludesTools() throws {
        let response: [String: Any] = ["thread": ["turns": [["items": [
            ["id": "u", "type": "userMessage", "content": [["type": "text", "text": "Question"]]],
            ["id": "t", "type": "commandExecution", "text": "private tool output"],
            ["id": "a", "type": "agentMessage", "text": "Answer"]
        ]]]]]
        let messages = try AgentChatEntry.parse(JSONSerialization.data(withJSONObject: response))
        #expect(messages.map(\.text) == ["Question", "Answer"])
        #expect(throws: AgentRoutingError.self) { try AgentChatEntry.parse(Data("{}".utf8)) }
    }
    @Test func queueTargetsExactExistingThreadAndPreservesText() throws {
        let text = "  Continue here: 'quotes', $(literal), 日本語\nsecond line  "
        let message = CodexChatMessage(session: session, text: text, clientID: UUID().uuidString)
        let parameters = try #require(JSONSerialization.jsonObject(with: message.parameters()) as? [String: Any])
        #expect(Set(parameters.keys) == ["threadId", "clientUserMessageId", "input"])
        #expect(parameters["threadId"] as? String == session.terminalSessionKey)
        let input = try #require(parameters["input"] as? [[String: Any]])
        #expect(input.count == 1 && input[0]["text"] as? String == text)
        let ack: [String: Any] = ["queuedSubmission": ["id": "queue-item", "clientUserMessageId": message.clientID, "input": input]]
        #expect(message.acknowledged(by: try JSONSerialization.data(withJSONObject: ack)))
        let other = CodexChatMessage(session: session, text: text, clientID: UUID().uuidString)
        #expect(!other.acknowledged(by: try JSONSerialization.data(withJSONObject: ack)))
        #expect(!message.acknowledged(by: Data("{}".utf8)))
    }
    @Test @MainActor func duplicateAndUncertainSubmissionsStayLatched() {
        let draft = AgentChatDraft()
        draft.text = "Continue the same thread"
        #expect(draft.begin(for: session) != nil)
        #expect(draft.begin(for: session) == nil)
        draft.sending = false; draft.uncertain = true
        #expect(draft.begin(for: session) == nil)
        #expect(draft.text == "Continue the same thread")
    }
    @Test func invalidDraftsAndUnprovenIdentitiesAreRejected() {
        for text in ["  \n", String(repeating: "x", count: 32_769)] {
            #expect(throws: AgentRoutingError.invalidResponse) {
                try CodexChatMessage(session: session, text: text, clientID: UUID().uuidString).parameters()
            }
        }
        let processOnly = SessionID(ownerInstanceID: "process", pid: 100, processStartTime: 1, terminalSessionKey: session.terminalSessionKey)
        #expect(throws: AgentRoutingError.invalidResponse) {
            try CodexChatMessage(session: processOnly, text: "Hello", clientID: UUID().uuidString).parameters()
        }
    }
    @Test @MainActor func queuedMessagesStayInHistoryUntilTheirExactServerEchoArrives() throws {
        let draft = AgentChatDraft()
        draft.updateHistory([AgentChatEntry(id: "old", role: "userMessage", text: "Repeat")])
        draft.text = "Repeat"
        let first = try #require(draft.begin(for: session))
        draft.recordQueued(first)
        draft.sending = false
        draft.text = "Repeat"
        let second = try #require(draft.begin(for: session))
        draft.recordQueued(second)
        #expect(draft.text.isEmpty)
        #expect(draft.history.count == 3)
        draft.updateHistory([AgentChatEntry(id: "old", role: "userMessage", text: "Repeat")])
        #expect(draft.history.count == 3, "A stale refresh must not erase queued messages")
        let echo = AgentChatEntry(id: "server", role: "userMessage", text: "Repeat", clientID: first.clientID)
        draft.updateHistory([AgentChatEntry(id: "old", role: "userMessage", text: "Repeat"), echo])
        #expect(draft.history.map(\.id) == ["old", "server", second.clientID])
        #expect(draft.history.last?.deliveryStatus == "chatQueued")
    }
    @Test @MainActor func pastedImageCanBeSentWithoutTextAndAckMustMatchItsContents() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        board.setData(png, forType: .png)
        let draft = AgentChatDraft()
        #expect(draft.pasteImages(from: board))
        #expect(draft.images.count == 1 && draft.canSubmit)
        let message = try #require(draft.begin(for: session))
        let params = try #require(JSONSerialization.jsonObject(with: message.parameters()) as? [String: Any])
        let input = try #require(params["input"] as? [[String: Any]])
        #expect(input.count == 1 && input[0]["type"] as? String == "image")
        #expect((input[0]["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        let ack: [String: Any] = ["queuedSubmission": ["id": "queued-image", "clientUserMessageId": message.clientID, "input": input]]
        #expect(message.acknowledged(by: try JSONSerialization.data(withJSONObject: ack)))
        let wrong: [String: Any] = ["queuedSubmission": ["id": "queued-image", "clientUserMessageId": message.clientID, "input": [["type": "image", "url": "different"]]]]
        #expect(!message.acknowledged(by: try JSONSerialization.data(withJSONObject: wrong)))
        draft.recordQueued(message)
        #expect(draft.images.isEmpty && draft.history.last?.images == message.images)
        #expect(!draft.pasteImages(from: board), "A pending send must not accept another paste")
    }
    @Test func historyPreservesImageOnlyMessagesAndClientIdentity() throws {
        let payload: [String: Any] = ["thread": ["turns": [["items": [
            ["id": "image-only", "clientId": "client", "type": "userMessage", "content": [["type": "image", "url": "data:image/png;base64,test"]]]
        ]]]]]
        let entry = try #require(AgentChatEntry.parse(JSONSerialization.data(withJSONObject: payload)).first)
        #expect(entry.images.count == 1 && entry.clientID == "client")
    }
    @Test @MainActor func invalidAndOversizedImagePayloadsKeepTheDraftUnsent() throws {
        let draft = AgentChatDraft()
        draft.images = ["https://example.com/image.png"]
        #expect(!draft.canSubmit && draft.begin(for: session) == nil)
        let oversized = "data:image/png;base64," + Data(repeating: 0, count: CodexWebSocketCodec.maximumBytes).base64EncodedString()
        #expect(throws: AgentRoutingError.invalidResponse) {
            try CodexChatMessage(session: session, text: "", clientID: UUID().uuidString, images: [oversized]).parameters()
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_CODEX_LIVE"] == "1", "Read-only queue capability check against existing daemon"))
    func readsExistingDesktopQueueWithoutSendingOrResuming() async throws {
        let sessions = CodexSessionObserver.scan(records: HostSessionDiscovery.snapshot())
        let session = try #require(sessions.first?.sessionID)
        let socket = CodexSocket()
        do {
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/app-server-control/app-server-control.sock").resolvingSymlinksInPath()
            try await socket.connect(path: path)
            let initialize = try JSONSerialization.data(withJSONObject: ["clientInfo": ["name": "island-chat-capability-check", "version": "0.2.0"], "capabilities": ["experimentalApi": true]])
            _ = try await socket.call("initialize", params: initialize)
            try await socket.notify("initialized")
            let params = try JSONSerialization.data(withJSONObject: ["threadId": session.terminalSessionKey, "limit": 1])
            let response = try await socket.call("thread/queue/list", params: params)
            let object = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
            #expect(object["data"] is [Any])
            print("Existing desktop-thread queue readable through official API; no messages sent or sessions resumed")
            await socket.close()
        } catch { await socket.close(); throw error }
    }
}
