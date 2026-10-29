import Foundation
import Combine
import IslandCore

struct CodexChatMessage: Sendable {
    let session: SessionID
    let text: String
    let clientID: String

    func parameters() throws -> Data {
        guard UUID(uuidString: session.terminalSessionKey) != nil,
              UUID(uuidString: clientID) != nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 32_768,
              session.ownerInstanceID == "codex-observed" || session.ownerInstanceID.hasPrefix("codex-daemon:") else {
            throw AgentRoutingError.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: [
            "threadId": session.terminalSessionKey,
            "clientUserMessageId": clientID,
            "input": [["type": "text", "text": text, "text_elements": []]]
        ])
    }
    func acknowledged(by data: Data) -> Bool {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queued = response["queuedSubmission"] as? [String: Any],
              let id = queued["id"] as? String, !id.isEmpty,
              queued["clientUserMessageId"] as? String == clientID,
              let inputs = queued["input"] as? [[String: Any]], inputs.count == 1,
              inputs[0]["type"] as? String == "text", inputs[0]["text"] as? String == text else { return false }
        return true
    }
}

@MainActor final class AgentChatDraft: ObservableObject {
    @Published var text = ""
    @Published var sending = false
    @Published var status: String?
    @Published var uncertain = false

    func begin(for session: SessionID) -> CodexChatMessage? {
        guard !sending, !uncertain else { return nil }
        let message = CodexChatMessage(session: session, text: text, clientID: UUID().uuidString)
        guard (try? message.parameters()) != nil else { status = "chatUnavailable"; return nil }
        sending = true; status = "chatSending"
        return message
    }
}

struct AgentChatEntry: Identifiable, Sendable {
    let id: String
    let role: String
    let text: String

    static func parse(_ data: Data) throws -> [AgentChatEntry] {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thread = response["thread"] as? [String: Any],
              let turns = thread["turns"] as? [[String: Any]] else { throw AgentRoutingError.unavailable }
        return turns.flatMap { turn -> [AgentChatEntry] in
            (turn["items"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String, let type = item["type"] as? String else { return nil }
                let text: String
                if type == "agentMessage" { text = item["text"] as? String ?? "" }
                else if type == "userMessage" {
                    text = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                } else { return nil }
                guard !text.isEmpty else { return nil }
                return AgentChatEntry(id: id, role: type, text: text)
            }
        }
    }
}
