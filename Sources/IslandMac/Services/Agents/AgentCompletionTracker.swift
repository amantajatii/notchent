import Foundation

/// Completion timestamps identify turns; open descriptors alone never trigger notifications.
struct AgentCompletionTracker {
    let startedAt: Date
    private var latest: [String: Date] = [:]
    init(startedAt: Date = Date()) { self.startedAt = startedAt }
    mutating func update(_ agents: [DiscoveredAgent]) -> [DiscoveredAgent] {
        agents.filter { agent in
            guard let thread = agent.sessionID?.terminalSessionKey, let date = agent.completedAt,
                  date > startedAt, date > (latest[thread] ?? .distantPast) else { return false }
            latest[thread] = date
            return true
        }
    }
}
