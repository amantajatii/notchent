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
        VStack(alignment: .leading, spacing: 12) {
            if registry.agents.isEmpty {
                Label(shell.text("noAgentSessions"), systemImage: "square.3.layers.3d")
                    .font(.system(size: 13, weight: .medium))
                Text(shell.text(registry.codexConnected ? "codexMonitoring" : "agentIntegrationPending"))
                    .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 520, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.62, green: 0.70, blue: 1)).frame(width: 6, height: 6)
                Text(title(agent)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 8)
                if let activity = agent.activity {
                    Text(shell.text(activity)).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
            HStack(spacing: 6) {
                Label(agent.kind == .codex ? "Codex" : agent.kind.rawValue, systemImage: "terminal.fill")
                    .foregroundStyle(Color(red: 0.65, green: 0.72, blue: 1))
                Text("· " + host(agent)).foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 11, weight: .medium))
            if let project = project(agent) {
                Text(URL(fileURLWithPath: project).lastPathComponent)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help(project).textSelection(.enabled)
            }
            if detailState.replyAgentID != agent.id, let summary = agent.summary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: agent.activity == "sessionCompleted" ? "checkmark" : "text.bubble")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.65, green: 0.72, blue: 1))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        if let activity = agent.activity {
                            Text(shell.text(activity)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(summary).font(.system(size: 12, weight: .medium))
                            .lineLimit(2).textSelection(.enabled)
                    }
                }
            }
            if detailState.replyAgentID == agent.id, let session = agent.sessionID, agent.kind == .codex {
                HStack {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { detailState.replyAgentID = nil } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .accessibilityLabel(shell.text("back"))
                }
                AgentConversationView(draft: registry.chatDraft(for: session), registry: registry, shell: shell,
                                      session: session, activity: agent.activity, summary: agent.summary)
                    .id(session)
            }
            if detailState.replyAgentID != agent.id {
            HStack(spacing: 8) {
                if let project = project(agent) {
                    Label(URL(fileURLWithPath: project).lastPathComponent, systemImage: "folder")
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                Spacer(minLength: 0)
                if let prompt = registry.prompt, prompt.sessionID == agent.sessionID {
                    Button(shell.text("openPrompt")) { shell.dispatch?(.openPrompt) }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                if let terminal = agent.ownedTerminal {
                    Button(shell.text("openTerminal")) {
                        guard shell.terminals.sessionIDs.contains(terminal), shell.terminals.isRunning(terminal) else { return }
                        shell.terminals.selectedID = terminal
                        shell.dispatch?(.show(.terminal))
                    }.padding(.horizontal, 10).padding(.vertical, 6)
                }
                if agent.sessionID != nil && agent.kind == .codex {
                    Button(shell.text("reply")) { detailState.replyAgentID = agent.id }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black).padding(.horizontal, 15).padding(.vertical, 7)
                        .background(.white, in: Capsule())
                }
            }
            }
        }
        .padding(14)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 16))
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
                        if draft.historyError { Text(shell.text("chatUnavailable")).foregroundStyle(.secondary).font(.caption) }
                        ForEach(draft.history) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role == "userMessage" ? "You" : "Codex").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                if !message.text.isEmpty {
                                    Text(message.text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                                    ChatImagePreview(source: image)
                                }
                                if let status = message.deliveryStatus {
                                    Text(shell.text(status)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 180)
                .onChange(of: draft.history.map(\.id)) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            if session.ownerInstanceID == "codex-observed" {
                Text(shell.text("desktopReplyUnavailable")).font(.caption).foregroundStyle(.secondary)
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
}

private struct ChatImagePreview: View {
    let source: String
    var body: some View {
        if source.hasPrefix("data:image/"), let comma = source.firstIndex(of: ","),
           let data = Data(base64Encoded: String(source[source.index(after: comma)...])), let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 160, maxHeight: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Attached image")
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
            HStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text(shell.text("chatPlaceholder")).font(.system(size: 13)).foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                    AgentChatInput(draft: draft, placeholder: shell.text("chatPlaceholder"), send: send)
                }.frame(height: 36)
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.5))
                        .background(canSend ? Color.white : Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shell.text("send"))
                .disabled(!canSend)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            if let status = draft.status {
                Text(shell.text(status)).font(.caption).foregroundStyle(.secondary)
            }
            if draft.uncertain {
                Button(shell.text("chatUnlock")) { draft.uncertain = false; draft.status = nil }
                    .font(.caption).padding(.vertical, 4)
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
