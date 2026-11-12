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
                IslandGlyph(symbol: "checkmark", tint: IslandDesign.success, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shell.text("agentFinished")).font(.system(size: 13, weight: .semibold))
                    Text(registry.completion?.sourceLabel?.components(separatedBy: "\n").first ?? "Codex")
                        .font(IslandDesign.footnote).foregroundStyle(IslandDesign.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(IslandDesign.tertiary)
            }.frame(width: 296, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(shell.text("agentFinished"))
    }
}
