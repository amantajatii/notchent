import SwiftUI
import IslandCore

@MainActor private final class AgentDetailState: ObservableObject {
    @Published var replyAgentID: String?
    @Published var contentHeight: CGFloat = 120
}

private struct AgentListHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AgentListView: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    @StateObject private var detailState = AgentDetailState()

    var body: some View {
        VStack(alignment: .leading, spacing: IslandDesign.gap) {
            if registry.agents.isEmpty {
                IslandEmptyState(title: shell.text("noAgentSessions"), symbol: "square.3.layers.3d",
                                 message: shell.text(registry.codexConnected ? "codexMonitoring" : "agentIntegrationPending"))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(registry.agents) { agent in detail(agent) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: AgentListHeight.self, value: geometry.size.height)
                    })
                }
                .frame(height: min(400, max(120, detailState.contentHeight)))
                .onPreferenceChange(AgentListHeight.self) { height in
                    if height > 0 { detailState.contentHeight = height }
                }
            }
        }
        .frame(width: IslandDesign.contentWidth, alignment: .leading)
        .onChange(of: registry.agents.map(\.id)) { _, ids in
            if let id = detailState.replyAgentID, !ids.contains(id) { detailState.replyAgentID = nil }
            if let id = registry.selectedAgentID, !ids.contains(id) { registry.selectedAgentID = nil }
        }
    }

    private func title(_ agent: DiscoveredAgent) -> String {
        agent.sourceLabel?.components(separatedBy: "\n").first ?? "\(agent.kind == .codex ? "Codex" : agent.kind.rawValue) · PID \(agent.pid)"
    }
    private func project(_ agent: DiscoveredAgent) -> String? {
        if let source = agent.sourceLabel {
            let path = source.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if !path.isEmpty { return path }
        }
        return agent.ownedTerminal.flatMap { shell.terminals.directory(for: $0)?.path }
    }
    private func host(_ agent: DiscoveredAgent) -> String {
        agent.ownedTerminal != nil ? "IslandMac" : (agent.host == .codexDesktop ? "Codex" : (agent.host?.rawValue ?? shell.text("hostUnknown")))
    }

    private func detail(_ agent: DiscoveredAgent) -> some View {
        let isReplying = detailState.replyAgentID == agent.id
        return VStack(alignment: .leading, spacing: 10) {
            header(agent)
            metadata(agent)
            if !isReplying, let summary = agent.summary, !summary.isEmpty { summaryRow(agent, summary: summary) }
            if isReplying, let session = agent.sessionID, agent.kind == .codex { chat(agent, session: session) }
            if !isReplying { actions(agent) }
        }
        .islandCard()
        .background(selectedBackground(agent), in: RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
        .overlay {
            if registry.selectedAgentID == agent.id {
                RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous)
                    .strokeBorder(IslandTint.agents.opacity(0.7), lineWidth: 1.5)
            }
        }
    }

    private func selectedBackground(_ agent: DiscoveredAgent) -> Color {
        registry.selectedAgentID == agent.id ? IslandTint.agents.opacity(0.18) : .clear
    }
    private func tint(_ agent: DiscoveredAgent) -> Color {
        switch agent.kind {
        case .codex: IslandTint.codex
        case .claudeCode: IslandTint.claude
        case .antigravity, .ohMyPi: IslandTint.agents
        }
    }
    private func statusColor(_ agent: DiscoveredAgent) -> Color {
        if agent.activity == "sessionCompleted" { return IslandDesign.success }
        if let prompt = registry.prompt, prompt.sessionID == agent.sessionID { return IslandDesign.warning }
        return IslandTint.agents
    }

    private func header(_ agent: DiscoveredAgent) -> some View {
        HStack(spacing: 8) {
            IslandGlyph(symbol: agent.kind == .codex ? "sparkles" : "terminal.fill", tint: tint(agent), size: 26)
            Circle().fill(statusColor(agent)).frame(width: 7, height: 7)
            Text(title(agent)).font(IslandDesign.title).lineLimit(2)
            Spacer(minLength: 8)
            if let activity = agent.activity {
                Text(shell.text(activity)).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandDesign.secondary).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(IslandDesign.fill, in: Capsule())
            }
        }
    }

    private func metadata(_ agent: DiscoveredAgent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "terminal.fill").foregroundStyle(tint(agent))
                Text((agent.kind == .codex ? "Codex" : agent.kind.rawValue) + " · " + host(agent))
            }
            if let project = project(agent) {
                Text(URL(fileURLWithPath: project).lastPathComponent)
                    .help(project).textSelection(.enabled)
            }
        }.font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
    }

    private func summaryRow(_ agent: DiscoveredAgent, summary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IslandGlyph(symbol: agent.activity == "sessionCompleted" ? "checkmark" : "text.bubble",
                        tint: agent.activity == "sessionCompleted" ? IslandDesign.success : tint(agent))
            VStack(alignment: .leading, spacing: 3) {
                if let activity = agent.activity {
                    Text(shell.text(activity)).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
                }
                Text(summary).font(IslandDesign.callout).lineLimit(2).textSelection(.enabled)
            }
        }
    }

    private func chat(_ agent: DiscoveredAgent, session: SessionID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandCardHeader("Chat", symbol: "bubble.left.and.bubble.right", tint: tint(agent)) {
                Button { detailState.replyAgentID = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(IslandIconButtonStyle(emphasis: .plain, tint: IslandDesign.primary))
                    .accessibilityLabel(shell.text("back"))
            }
            AgentConversationView(draft: registry.chatDraft(for: session), registry: registry, shell: shell,
                                  session: session, activity: agent.activity, summary: agent.summary)
                .id(session)
        }
    }

    private func actions(_ agent: DiscoveredAgent) -> some View {
        HStack(spacing: 8) {
            if let project = project(agent) {
                Label(URL(fileURLWithPath: project).lastPathComponent, systemImage: "folder")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(IslandDesign.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(IslandDesign.fill, in: Capsule())
            }
            Spacer(minLength: 0)
            if let prompt = registry.prompt, prompt.sessionID == agent.sessionID {
                Button(shell.text("openPrompt")) { shell.dispatch?(.openPrompt) }
                    .buttonStyle(IslandPillButtonStyle())
            }
            if let terminal = agent.ownedTerminal {
                Button(shell.text("openTerminal")) {
                    guard shell.terminals.sessionIDs.contains(terminal), shell.terminals.isRunning(terminal) else { return }
                    shell.terminals.selectedID = terminal
                    shell.dispatch?(.show(.terminal))
                }.buttonStyle(IslandPillButtonStyle())
            }
            if agent.sessionID != nil && agent.kind == .codex {
                Button(shell.text("reply")) { detailState.replyAgentID = agent.id }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: tint(agent)))
            }
        }
    }
}

private struct AgentConversationView: View {
    @ObservedObject var draft: AgentChatDraft
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    let session: SessionID
    let activity: String?
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if draft.historyLoading && draft.history.isEmpty { ProgressView().controlSize(.small) }
                        if draft.historyError { Text(shell.text("chatUnavailable")).foregroundStyle(IslandDesign.secondary).font(IslandDesign.caption) }
                        ForEach(draft.history) { message in bubble(message) }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 180)
                .onChange(of: draft.history.map(\.id)) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            if session.ownerInstanceID == "codex-observed" {
                Text(shell.text("desktopReplyUnavailable")).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
            }
            AgentChatComposer(draft: draft, registry: registry, shell: shell, session: session)
        }
        .task(id: [String(draft.queuedCount), String(registry.chatRevisions[session.terminalSessionKey, default: 0]), activity ?? "", summary ?? ""]) {
            draft.historyLoading = true
            defer { draft.historyLoading = false }
            do {
                let entries = try await registry.readChat(for: session)
                guard !Task.isCancelled else { return }
                draft.updateHistory(entries); draft.historyError = false
            } catch {
                if !Task.isCancelled { draft.historyError = true }
            }
        }
    }
    private func bubble(_ message: AgentChatEntry) -> some View {
        let isUser = message.role == "userMessage"
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text).font(IslandDesign.callout).textSelection(.enabled)
                }
                ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                    ChatImagePreview(source: image)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(IslandDesign.primary)
            .background(isUser ? IslandTint.agents : IslandDesign.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(isUser ? "You" : "Codex").font(IslandDesign.footnote).foregroundStyle(IslandDesign.tertiary)
            if let status = message.deliveryStatus {
                Text(shell.text(status)).font(IslandDesign.footnote).foregroundStyle(IslandDesign.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 56)
    }
}

private struct ChatImagePreview: View {
    let source: String
    var body: some View {
        if source.hasPrefix("data:image/"), let comma = source.firstIndex(of: ","),
           let data = Data(base64Encoded: String(source[source.index(after: comma)...])), let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 160, maxHeight: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).accessibilityLabel("Attached image")
        } else {
            Label("Image", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AgentChatComposer: View {
    @ObservedObject var draft: AgentChatDraft
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    let session: SessionID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !draft.images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(draft.images.enumerated()), id: \.offset) { index, image in
                            ChatImagePreview(source: image)
                                .overlay(alignment: .topTrailing) {
                                    Button { draft.images.remove(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black)
                                    }.buttonStyle(.plain).accessibilityLabel(shell.text("chatRemoveImage"))
                                        .disabled(draft.sending || draft.uncertain)
                                }
                        }
                    }.padding(2)
                }
            }
            HStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text(shell.text("chatPlaceholder")).font(IslandDesign.body).foregroundStyle(IslandDesign.secondary)
                            .allowsHitTesting(false)
                    }
                    AgentChatInput(draft: draft, placeholder: shell.text("chatPlaceholder"), send: send)
                }.frame(height: 32)
                Button { send() } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(IslandIconButtonStyle(emphasis: canSend ? .filled : .plain, tint: IslandTint.agents))
                    .accessibilityLabel(shell.text("send"))
                    .disabled(!canSend)
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 5)
            .background(IslandDesign.fill, in: RoundedRectangle(cornerRadius: IslandDesign.rowRadius + 4, style: .continuous))
            if let status = draft.status {
                Text(shell.text(status)).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
            }
            if draft.uncertain {
                Button(shell.text("chatUnlock")) { draft.uncertain = false; draft.status = nil }
                    .buttonStyle(IslandPillButtonStyle())
            }
        }
        .onDisappear { shell.dispatch?(.inputChanged(false)) }
    }
    private var canSend: Bool {
        registry.codexConnected && draft.canSubmit
    }
    private func send() {
        guard canSend else { return }
        registry.sendChat(to: session)
    }
}
