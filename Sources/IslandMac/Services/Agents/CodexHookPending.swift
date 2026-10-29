import Foundation
import IslandCore

struct CodexHookPending: Sendable {
    let envelope: CodexHookEnvelope
    let event: String
    let prompt: AgentPrompt

    static func decode(_ envelope: CodexHookEnvelope, records: [HostSessionDiscovery.ProcessRecord], helperPath: String, now: Date = Date()) -> Self? {
        let age = now.timeIntervalSince(envelope.createdAt)
        guard age >= -5, age < 120, envelope.input.count <= 65_536,
              let process = records.first(where: { $0.pid == envelope.pid && $0.birth == envelope.birth && $0.uid == getuid() && $0.executable == helperPath }) else { return nil }
        let byPID = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var next = process.parent; var seen = Set<Int32>(); var codex = false
        while let parent = byPID[next], seen.insert(next).inserted, seen.count <= 128 {
            if parent.uid == getuid(), HostSessionDiscovery.kind(for: parent.executable) == .codex { codex = true; break }
            next = parent.parent
        }
        guard codex, let object = try? JSONSerialization.jsonObject(with: envelope.input) as? [String: Any],
              let thread = object["session_id"] as? String, UUID(uuidString: thread) != nil,
              let turn = object["turn_id"] as? String, !turn.isEmpty,
              let cwd = object["cwd"] as? String, cwd.hasPrefix("/"),
              let event = object["hook_event_name"] as? String,
              let name = object["tool_name"] as? String,
              let input = object["tool_input"] as? [String: Any] else { return nil }
        let text: String
        let choices: [PromptChoice]
        if event == "PermissionRequest" {
            guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
                  let details = String(data: data, encoding: .utf8) else { return nil }
            text = name + "\n\n" + details
            choices = [PromptChoice(id: "hookAllow", text: "Allow once"), PromptChoice(id: "hookDeny", text: "Deny"), PromptChoice(id: "hookContinue", text: "Answer in Codex")]
        } else if event == "PreToolUse", ["request_user_input", "request_user_input_async"].contains(name.split(separator: ".").last.map(String.init) ?? "") {
            guard let questions = input["questions"] as? [[String: Any]], !questions.isEmpty, questions.count <= 3 else { return nil }
            var lines: [String] = []
            for question in questions {
                guard question["isSecret"] as? Bool != true,
                      let questionText = question["question"] as? String ?? question["title"] as? String else { return nil }
                lines.append(questionText)
                for option in question["options"] as? [[String: Any]] ?? [] {
                    if let label = option["label"] as? String { lines.append("• " + label) }
                }
                if let options = question["options"] as? [String] { lines.append(contentsOf: options.map { "• " + $0 }) }
            }
            text = lines.joined(separator: "\n")
            // A PreToolUse hook cannot return the tool's answer. Hand back to its original UI.
            choices = [PromptChoice(id: "hookContinue", text: "Answer in Codex")]
        } else { return nil }
        let session = SessionID(ownerInstanceID: "codex-hook:" + envelope.id.uuidString, pid: envelope.pid,
                                processStartTime: envelope.birth, terminalSessionKey: thread)
        let prompt = AgentPrompt(id: PromptID(sessionID: session, localRequestID: envelope.id.uuidString), revision: 1,
                                 text: text, choices: choices, acceptsText: false,
                                 sourceLabel: "Codex · " + URL(fileURLWithPath: cwd).lastPathComponent + "\n" + cwd)
        return Self(envelope: envelope, event: event, prompt: prompt)
    }
    func isLive(mailbox: CodexHookMailbox, records: [HostSessionDiscovery.ProcessRecord]? = nil, now: Date = Date()) -> Bool {
        let helper = mailbox.root.deletingLastPathComponent().appendingPathComponent("IslandHook").path
        guard Self.decode(envelope, records: records ?? HostSessionDiscovery.snapshot(), helperPath: helper, now: now) != nil,
              mailbox.secureDirectory(mailbox.directory(envelope.id)),
              let data = mailbox.read(mailbox.directory(envelope.id).appendingPathComponent("request.json")),
              let current = try? JSONDecoder().decode(CodexHookEnvelope.self, from: data) else { return false }
        return current == envelope
    }
}
