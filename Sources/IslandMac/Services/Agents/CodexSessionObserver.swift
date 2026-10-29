import Foundation
import Darwin
import IslandCore

/// Observes only session files currently held open by a same-user Codex process.
struct CodexSessionObserver {
    struct Snapshot {
        let id: String
        let project: String
        var status = "sessionActivityUnknown"
        var summary: String?
        var activityAt: Date?
        var modifiedAt = Date.distantPast
    }
    static func isVisible(_ snapshot: Snapshot, now: Date = Date()) -> Bool {
        if snapshot.status == "sessionWorking" { return true }
        let age = now.timeIntervalSince(snapshot.activityAt ?? snapshot.modifiedAt)
        let retention: TimeInterval = snapshot.status == "sessionActivityUnknown" ? 30 : 30 * 60
        return age >= -5 && age <= retention
    }
    static func parse(header: Data, tail: Data) -> Snapshot? {
        guard let line = header.split(separator: 10).first,
              let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              record["type"] as? String == "session_meta",
              let metadata = record["payload"] as? [String: Any],
              let id = metadata["id"] as? String, UUID(uuidString: id) != nil,
              let cwd = metadata["cwd"] as? String, cwd.hasPrefix("/") else { return nil }
        var snapshot = Snapshot(id: id, project: cwd)
        var activeTurn: String?
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        // A partial final record is never treated as an event.
        let lines = tail.split(separator: 10, omittingEmptySubsequences: false).dropLast()
        for line in lines {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  record["type"] as? String == "event_msg",
                  let event = record["payload"] as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "task_started", "turn_started":
                activeTurn = event["turn_id"] as? String
                snapshot.status = "sessionWorking"; snapshot.summary = nil
            case "task_complete", "turn_complete":
                if let activeTurn, let turn = event["turn_id"] as? String, turn != activeTurn { continue }
                snapshot.status = "sessionCompleted"
                snapshot.summary = (event["last_agent_message"] as? String).map { String($0.prefix(32_768)) }
            case "turn_aborted":
                if let activeTurn, let turn = event["turn_id"] as? String, turn != activeTurn { continue }
                snapshot.status = "sessionInterrupted"; snapshot.summary = nil
            default: continue
            }
            let stamp = record["timestamp"] as? String ?? ""
            snapshot.activityAt = fractional.date(from: stamp) ?? seconds.date(from: stamp)
        }
        return snapshot
    }
    static func scan(records: [HostSessionDiscovery.ProcessRecord]) -> [DiscoveredAgent] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").resolvingSymlinksInPath().path + "/"
        var sessions: [String: DiscoveredAgent] = [:]
        for process in records where process.uid == getuid() && HostSessionDiscovery.kind(for: process.executable) == .codex {
            for path in paths(pid: process.pid) where path.hasPrefix(root) {
                guard let snapshot = read(path), isVisible(snapshot), HostSessionDiscovery.snapshotIdentity(process.pid) == process.birth else { continue }
                let identity = SessionID(ownerInstanceID: "codex-observed", pid: process.pid, processStartTime: process.birth, terminalSessionKey: snapshot.id)
                let name = URL(fileURLWithPath: snapshot.project).lastPathComponent
                sessions[snapshot.id] = DiscoveredAgent(pid: process.pid, birth: process.birth, kind: .codex,
                    host: .codexDesktop, sessionID: identity, ownedTerminal: nil, reason: "sessionReadOnly",
                    sourceLabel: name + " · " + String(snapshot.id.prefix(8)) + "\n" + snapshot.project,
                    activity: snapshot.status, summary: snapshot.summary,
                    completedAt: snapshot.status == "sessionCompleted" ? snapshot.activityAt : nil)
            }
        }
        return sessions.keys.sorted().compactMap { sessions[$0] }
    }
    private static func read(_ path: String) -> Snapshot? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG else { return nil }
        do {
            let header = try file.read(upToCount: 65_536) ?? Data()
            let size = try file.seekToEnd()
            // shortcut: cap each scan at 256 KiB per open session; use incremental offsets if session counts grow.
            try file.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
            let tail = try file.read(upToCount: 262_144) ?? Data()
            var snapshot = parse(header: header, tail: tail)
            snapshot?.modifiedAt = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            return snapshot
        } catch { return nil }
    }
    static func chatEntry(line: Data, index: Int) -> AgentChatEntry? {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              record["type"] as? String == "response_item",
              let payload = record["payload"] as? [String: Any], payload["type"] as? String == "message",
              let role = payload["role"] as? String, role == "user" || role == "assistant",
              role != "assistant" || payload["phase"] as? String == "final_answer",
              let content = payload["content"] as? [[String: Any]] else { return nil }
        let text = content.compactMap { part -> String? in
            let type = part["type"] as? String
            guard type == "input_text" || type == "output_text" else { return nil }
            guard let text = part["text"] as? String else { return nil }
            if role == "user" && ["<environment_context>", "<external_codex_apps_open_page>"].contains(where: { text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix($0) }) { return nil }
            return text
        }.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        return AgentChatEntry(id: "\(index)", role: role == "user" ? "userMessage" : "agentMessage", text: text)
    }

    static func readChat(session: SessionID) throws -> [AgentChatEntry] {
        guard session.ownerInstanceID == "codex-observed", UUID(uuidString: session.terminalSessionKey) != nil,
              HostSessionDiscovery.snapshotIdentity(session.pid) == session.processStartTime else { throw AgentRoutingError.unavailable }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").resolvingSymlinksInPath().path + "/"
        for path in paths(pid: session.pid) where path.hasPrefix(root) {
            let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { continue }
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? file.close() }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG else { continue }
            let header = try file.read(upToCount: 65_536) ?? Data()
            guard parse(header: header, tail: Data())?.id == session.terminalSessionKey else { continue }
            try file.seek(toOffset: 0)
            var buffer = Data(), result: [AgentChatEntry] = []
            var index = 0
            while let chunk = try file.read(upToCount: 65_536), !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    if let entry = chatEntry(line: line, index: index) { result.append(entry) }
                    index += 1
                }
            }
            guard HostSessionDiscovery.snapshotIdentity(session.pid) == session.processStartTime else { throw AgentRoutingError.identityChanged }
            return result
        }
        throw AgentRoutingError.unavailable
    }

    private static func paths(pid: Int32) -> [String] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0, bytes < 4_194_304 else { return [] }
        var entries = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride + 32)
        let used = entries.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return [] }
        var result = Set<String>()
        for entry in entries.prefix(Int(used) / MemoryLayout<proc_fdinfo>.stride) where entry.proc_fdtype == PROX_FDTYPE_VNODE {
            var vnode = vnode_fdinfowithpath()
            let count = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, entry.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, count) == count else { continue }
            let path = withUnsafePointer(to: &vnode.pvip.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let name = URL(fileURLWithPath: path).lastPathComponent
            if name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") { result.insert(path) }
        }
        return result.sorted()
    }
}
