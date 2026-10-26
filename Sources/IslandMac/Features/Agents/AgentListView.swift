import SwiftUI
import IslandCore

struct AgentListView: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(shell.text("agentMetadataNotice")).font(.caption).foregroundStyle(.secondary)
                if registry.unmappedCount > 0 { Text("\(shell.text("unmappedAgents")): \(registry.unmappedCount)").font(.caption) }
                if registry.agents.isEmpty { Text(shell.text("noDetectedAgents")) }
                ForEach(registry.agents) { agent in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(agent.kind.rawValue) · PID \(agent.pid)").font(.headline)
                        Text(agent.ownedTerminal.flatMap { shell.terminals.directory(for: $0)?.path } ?? shell.text("projectUnknown"))
                            .font(.caption).textSelection(.enabled)
                        Text(agent.ownedTerminal != nil ? "IslandMac" : (agent.host?.rawValue ?? shell.text("hostUnknown"))).font(.caption)
                        Text(shell.text("agentStatusUnknown")).font(.caption)
                        Text(shell.text(agent.reason)).font(.caption).foregroundStyle(.secondary)
                        Text(shell.text("agentReadSendUnavailable")).font(.caption).foregroundStyle(.secondary)
                        if let terminal = agent.ownedTerminal {
                            Button(shell.text("openTerminal")) {
                                guard shell.terminals.sessionIDs.contains(terminal), shell.terminals.isRunning(terminal) else { return }
                                shell.terminals.selectedID = terminal; shell.dispatch?(.show(.terminal))
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(4)
        }.frame(width: 560, height: 270)
    }
}
