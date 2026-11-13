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
func readInput() -> Data {
    var input = Data()
    while input.count <= ClaudeUsageRecord.maximumInputBytes {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: 8192), !chunk.isEmpty else { break }
        input.append(chunk)
    }
    return input
}

/// Claude Code status line: relay `rate_limits` to Notchent and print a short status.
/// A failed relay never breaks the status line itself.
func runClaudeStatusLine() -> Data {
    let input = readInput()
    let relay = ClaudeUsageRelay()
    let fresh = ClaudeUsageRecord.extract(statusLineInput: input)
    if let fresh { try? relay.write(fresh) }
    return Data(ClaudeStatusLine.text(statusLineInput: input, record: fresh ?? relay.read()?.current(at: Date())).utf8)
}

/// The nearest Claude Code ancestor (hooks may run through a shell), with its birth time.
func claudeProcess() -> (pid: Int32, birth: UInt64)? {
    var pid = getppid()
    for _ in 0..<8 where pid > 1 {
        var path = [CChar](repeating: 0, count: 4096)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0, ClaudeExecutable.matches(String(cString: path)) {
            return (pid, info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
        }
        pid = Int32(info.pbi_ppid)
    }
    return nil
}

/// Claude Code hook: record session state for the island. Prints nothing and always succeeds,
/// so it can never block or alter Claude Code (stdout of some hooks becomes model context).
func runClaudeHook() {
    let input = readInput()
    guard input.count <= ClaudeSessionStore.maximumInputBytes else { return }
    try? ClaudeSessionStore().apply(payload: input, process: claudeProcess())
}

switch CommandLine.arguments.dropFirst().first {
case "claude-hook":
    runClaudeHook()
case "claude-statusline":
    FileHandle.standardOutput.write(runClaudeStatusLine())
    FileHandle.standardOutput.write(Data([10]))
default:
    FileHandle.standardOutput.write((try? run()) ?? Data("{}".utf8))
    FileHandle.standardOutput.write(Data([10]))
}
