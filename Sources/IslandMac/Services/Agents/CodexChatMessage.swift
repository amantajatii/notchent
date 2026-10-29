import AppKit
import Combine
import IslandCore

struct CodexChatMessage: Sendable {
    let session: SessionID
    let text: String
    let clientID: String
    var images: [String] = []

    static func input(text: String, images: [String]) -> [[String: Any]] {
        let textInput: [[String: Any]] = text.isEmpty ? [] : [["type": "text", "text": text, "text_elements": []]]
        return textInput + images.map { ["type": "image", "url": $0] }
    }
    static func validContent(text: String, images: [String]) -> Bool {
        guard (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty),
              text.utf8.count <= 32_768,
              images.allSatisfy({ image in
                  let prefix = "data:image/png;base64,"
                  guard image.hasPrefix(prefix), image.utf8.count < CodexWebSocketCodec.maximumBytes,
                        let data = Data(base64Encoded: String(image.dropFirst(prefix.count))),
                        NSBitmapImageRep(data: data) != nil else { return false }
                  return true
              }),
              let data = try? JSONSerialization.data(withJSONObject: input(text: text, images: images)) else { return false }
        return data.count < CodexWebSocketCodec.maximumBytes - 1024
    }
    func parameters() throws -> Data {
        guard UUID(uuidString: session.terminalSessionKey) != nil,
              UUID(uuidString: clientID) != nil,
              Self.validContent(text: text, images: images),
              session.ownerInstanceID == "codex-observed" || session.ownerInstanceID.hasPrefix("codex-daemon:") else {
            throw AgentRoutingError.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: [
            "threadId": session.terminalSessionKey,
            "clientUserMessageId": clientID,
            "input": Self.input(text: text, images: images)
        ])
    }
    func acknowledged(by data: Data) -> Bool {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queued = response["queuedSubmission"] as? [String: Any],
              let id = queued["id"] as? String, !id.isEmpty,
              queued["clientUserMessageId"] as? String == clientID,
              let inputs = queued["input"] as? [[String: Any]],
              inputs.count == Self.input(text: text, images: images).count else { return false }
        // The server may add default fields; match every submitted text/image in order.
        return zip(inputs, Self.input(text: text, images: images)).allSatisfy { received, sent in
            received["type"] as? String == sent["type"] as? String &&
            (sent["type"] as? String == "text" ? received["text"] as? String == sent["text"] as? String : received["url"] as? String == sent["url"] as? String)
        }
    }
}

@MainActor final class AgentChatDraft: ObservableObject {
    @Published var text = ""
    @Published var images: [String] = []
    @Published var sending = false
    @Published var status: String?
    @Published var uncertain = false
    @Published var historyLoading = false
    @Published var historyError = false
    @Published private(set) var history: [AgentChatEntry] = []
    @Published private(set) var queuedCount = 0
    private var pending: [AgentChatEntry] = []

    var canSubmit: Bool { !sending && !uncertain && CodexChatMessage.validContent(text: text, images: images) }

    func pasteImages(from pasteboard: NSPasteboard) -> Bool {
        guard !sending, !uncertain,
              let pasted = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], !pasted.isEmpty else { return false }
        let encoded = pasted.compactMap { image -> String? in
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
            return "data:image/png;base64," + png.base64EncodedString()
        }
        guard encoded.count == pasted.count, CodexChatMessage.validContent(text: text, images: images + encoded) else {
            status = "chatImageTooLarge"; return true
        }
        images += encoded; status = nil
        return true
    }
    func begin(for session: SessionID) -> CodexChatMessage? {
        guard !sending, !uncertain else { return nil }
        let message = CodexChatMessage(session: session, text: text, clientID: UUID().uuidString, images: images)
        guard (try? message.parameters()) != nil else { status = "chatUnavailable"; return nil }
        sending = true; status = "chatSending"
        return message
    }
    func recordQueued(_ message: CodexChatMessage) {
        let entry = AgentChatEntry(id: message.clientID, role: "userMessage", text: message.text,
                                   images: message.images, clientID: message.clientID, deliveryStatus: "chatQueued")
        pending.append(entry); history.append(entry); queuedCount += 1
        if text == message.text { text = "" }
        if images == message.images { images = [] }
        status = "chatQueued"
    }
    func updateHistory(_ entries: [AgentChatEntry]) {
        let echoed = Set(entries.flatMap { [$0.id, $0.clientID].compactMap { $0 } })
        pending.removeAll { echoed.contains($0.id) }
        history = entries + pending
        if pending.isEmpty && status == "chatQueued" { status = nil }
    }
}

struct AgentChatEntry: Identifiable, Sendable {
    let id: String
    let role: String
    let text: String
    var images: [String] = []
    var clientID: String? = nil
    var deliveryStatus: String? = nil

    static func parse(_ data: Data) throws -> [AgentChatEntry] {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thread = response["thread"] as? [String: Any],
              let turns = thread["turns"] as? [[String: Any]] else { throw AgentRoutingError.unavailable }
        return turns.flatMap { turn -> [AgentChatEntry] in
            (turn["items"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String, let type = item["type"] as? String else { return nil }
                let text: String
                var images: [String] = []
                if type == "agentMessage" { text = item["text"] as? String ?? "" }
                else if type == "userMessage" {
                    let content = item["content"] as? [[String: Any]] ?? []
                    text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                    images = content.compactMap { part in
                        switch part["type"] as? String {
                        case "image": return part["url"] as? String ?? part["fileId"] as? String
                        case "localImage": return part["path"] as? String
                        default: return nil
                        }
                    }
                } else { return nil }
                guard !text.isEmpty || !images.isEmpty else { return nil }
                return AgentChatEntry(id: id, role: type, text: text, images: images, clientID: item["clientId"] as? String)
            }
        }
    }
}
