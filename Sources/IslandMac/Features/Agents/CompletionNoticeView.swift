import SwiftUI
import IslandCore

struct CompletionNoticeView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var registry: AgentRegistry
    var body: some View {
        Button {
            registry.selectedAgentID = registry.completion?.id
            shell.dispatch?(.reveal(.agents))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color(white: 0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(shell.text("agentFinished")).font(.system(size: 12, weight: .semibold))
                    Text(registry.completion?.sourceLabel?.components(separatedBy: "\n").first ?? "Codex")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: 296, height: 28).contentShape(Rectangle())
        }.accessibilityLabel(shell.text("agentFinished"))
    }
}
