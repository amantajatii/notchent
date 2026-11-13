import SwiftUI
import IslandCore

/// "Task complete" card: which agent, which project, and the gist of its last reply.
struct CompletionNoticeView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var registry: AgentRegistry
    private static let width: CGFloat = 300
    private static let glyphSize: CGFloat = 30

    var body: some View {
        let agent = registry.completion
        Button {
            registry.selectedAgentID = agent?.id
            shell.dispatch?(.reveal(.agents))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AgentBadge(kind: agent?.kind ?? .codex, size: Self.glyphSize)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text((agent?.kind ?? .codex).displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AgentBadge.tint(for: agent?.kind ?? .codex))
                        Text(shell.text("taskComplete")).font(.system(size: 13, weight: .semibold))
                    }
                    if let project = agent.flatMap(Self.project) {
                        Text(project).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary).lineLimit(1)
                    }
                    if let summary = agent?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                        Text(summary).font(IslandDesign.caption).foregroundStyle(IslandDesign.tertiary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shell.text("taskComplete"))
    }

    /// The project folder name, without Codex's short thread suffix.
    private static func project(_ agent: DiscoveredAgent) -> String? {
        guard let first = agent.sourceLabel?.components(separatedBy: "\n").first else { return nil }
        return first.components(separatedBy: " · ").first
    }
}

/// A round badge per agent: Claude Code in its warm clay tone, everything else neutral.
struct AgentBadge: View {
    let kind: AgentKind
    let size: CGFloat

    static func tint(for kind: AgentKind) -> Color {
        kind == .claudeCode ? Color(red: 0.85, green: 0.47, blue: 0.34) : IslandDesign.secondary
    }

    var body: some View {
        Image(systemName: kind == .claudeCode ? "asterisk" : "chevron.left.forwardslash.chevron.right")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(kind == .claudeCode ? .white : IslandDesign.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(kind == .claudeCode ? Self.tint(for: kind) : IslandDesign.fill))
            .accessibilityHidden(true)
    }
}
