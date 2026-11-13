import Foundation
import IslandCore

/// Joins hook-written Claude Code session records to live Claude processes.
enum ClaudeSessionObserver {
    /// Claude agents enriched with hook state. A record counts only while its exact process
    /// (pid and birth time) is alive; the newest session wins when one process ran several.
    static func merge(found: [DiscoveredAgent], records: [ClaudeSessionRecord]) -> [DiscoveredAgent] {
        let latest = Dictionary(records.compactMap { record -> (String, ClaudeSessionRecord)? in
            guard let pid = record.pid, let birth = record.birth else { return nil }
            return ("\(pid):\(birth)", record)
        }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        return found.filter { $0.kind == .claudeCode }.compactMap { agent in
            guard let record = latest["\(agent.pid):\(agent.birth)"] else {
                // Without a hook record, keep the old rule: show only processes with a known host.
                return agent.ownedTerminal != nil || agent.host != nil ? agent : nil
            }
            return enriched(agent, with: record)
        }
    }

    private static func enriched(_ agent: DiscoveredAgent, with record: ClaudeSessionRecord) -> DiscoveredAgent {
        let identity = SessionID(ownerInstanceID: "claude-hook", pid: agent.pid, processStartTime: agent.birth,
                                 terminalSessionKey: record.sessionID)
        let project = URL(fileURLWithPath: record.cwd).lastPathComponent
        var result = DiscoveredAgent(pid: agent.pid, birth: agent.birth, kind: .claudeCode, host: agent.host,
                                     sessionID: agent.sessionID ?? identity, ownedTerminal: agent.ownedTerminal, reason: "claudeHook")
        result.sourceLabel = (project.isEmpty ? "Claude Code" : project) + "\n" + record.cwd
        result.activity = activity(record.state)
        result.summary = record.state == .done ? record.lastMessage : nil
        result.completedAt = record.state == .done ? record.completedAt : nil
        return result
    }

    private static func activity(_ state: ClaudeSessionRecord.State) -> String? {
        switch state {
        case .idle: nil
        case .working: "sessionWorking"
        case .waiting: "sessionWaiting"
        case .done: "sessionCompleted"
        }
    }
}

extension AgentKind {
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .antigravity: "Antigravity"
        case .ohMyPi: "Oh My Pi"
        }
    }
}
