import Foundation
import Darwin
import IslandCore

// No decision on failure: Codex's original approval/question flow remains in control.
func run() throws -> Data {
    var input = Data()
    while input.count <= 65_536 {
        guard let chunk = try FileHandle.standardInput.read(upToCount: min(8192, 65_537 - input.count)), !chunk.isEmpty else { break }
        input.append(chunk)
    }
    guard input.count <= 65_536,
          let payload = try JSONSerialization.jsonObject(with: input) as? [String: Any],
          let event = payload["hook_event_name"] as? String,
          ["PermissionRequest", "PreToolUse"].contains(event),
          let thread = payload["session_id"] as? String, UUID(uuidString: thread) != nil,
          let turn = payload["turn_id"] as? String, !turn.isEmpty,
          let cwd = payload["cwd"] as? String, cwd.hasPrefix("/"),
          payload["tool_input"] is [String: Any] else { return Data("{}".utf8) }
    if event == "PreToolUse" {
        let name = (payload["tool_name"] as? String ?? "").split(separator: ".").last.map(String.init) ?? ""
        guard ["request_user_input", "request_user_input_async"].contains(name),
              let toolInput = payload["tool_input"] as? [String: Any],
              let questions = toolInput["questions"] as? [[String: Any]], !questions.isEmpty,
              questions.allSatisfy({ $0["isSecret"] as? Bool != true }) else { return Data("{}".utf8) }
    }
    let mailbox = CodexHookMailbox()
    guard mailbox.secureDirectory(mailbox.root),
          let data = mailbox.read(mailbox.root.appendingPathComponent("host.json")),
          let host = try? JSONDecoder().decode(CodexHookHost.self, from: data),
          CodexHookMailbox.birth(host.pid) == host.birth,
          let birth = CodexHookMailbox.birth(getpid()) else { return Data("{}".utf8) }
    var hostPath = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(host.pid, &hostPath, UInt32(hostPath.count)) > 0,
          URL(fileURLWithPath: String(cString: hostPath)).lastPathComponent == "IslandMac" else { return Data("{}".utf8) }
    let envelope = CodexHookEnvelope(pid: getpid(), birth: birth, input: input)
    let directory = mailbox.directory(envelope.id)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    try mailbox.write(JSONEncoder().encode(envelope), to: directory.appendingPathComponent("request.json"))
    let deadline = ProcessInfo.processInfo.systemUptime + 120
    while ProcessInfo.processInfo.systemUptime < deadline {
        guard CodexHookMailbox.birth(host.pid) == host.birth else { return Data("{}".utf8) }
        if let response = mailbox.read(directory.appendingPathComponent("response.json")),
           let choice = String(data: response, encoding: .utf8) {
            return try CodexHookMailbox.decision(event: event, choice: choice)
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    return Data("{}".utf8)
}
let output = (try? run()) ?? Data("{}".utf8)
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data([10]))
