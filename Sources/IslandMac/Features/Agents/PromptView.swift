import SwiftUI
import IslandCore

@MainActor private final class ReplyDraft: ObservableObject {
    @Published var text = ""
    @Published var answers: [String: String] = [:]
    @Published var contentHeight: CGFloat = 80
}
private struct PromptTextHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PromptView: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    @StateObject private var reply = ReplyDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = registry.prompt {
                HStack {
                    Label((prompt.sessionID.ownerInstanceID.hasPrefix("codex-daemon:") || prompt.sessionID.ownerInstanceID.hasPrefix("codex-hook:")) ? "Codex" : "PID \(prompt.sessionID.pid)", systemImage: "terminal")
                    Spacer()
                    if shell.state.pendingCount > 1 { Text("\(shell.text("pending")): \(shell.state.pendingCount)") }
                }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let source = prompt.sourceLabel { Text(source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if !prompt.questions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(prompt.questions, id: \.id) { question in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(question.text).font(.system(size: 13, weight: .medium))
                                    ForEach(question.choices, id: \.id) { choice in
                                        Button { reply.answers[question.id] = choice.id } label: {
                                            HStack {
                                                Image(systemName: reply.answers[question.id] == choice.id ? "largecircle.fill.circle" : "circle")
                                                Text(choice.text).frame(maxWidth: .infinity, alignment: .leading)
                                            }.font(.system(size: 12)).padding(10)
                                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                    if question.acceptsText {
                                        TextField(shell.text("reply"), text: Binding(get: { reply.answers[question.id] ?? "" }, set: { reply.answers[question.id] = $0 }))
                                    }
                                }
                            }
                        }
                    }.frame(height: 240)
                        .disabled(registry.submitted.contains(prompt.id))
                    Button(shell.text("send")) { _ = registry.respond(.answers(reply.answers), to: prompt) }
                        .disabled(registry.submitted.contains(prompt.id) || !prompt.accepts(answers: reply.answers))
                } else {
                ScrollView {
                    Text(prompt.text).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { geometry in Color.clear.preference(key: PromptTextHeight.self, value: geometry.size.height) })
                }.frame(height: min(240, max(28, reply.contentHeight)))
                    .onPreferenceChange(PromptTextHeight.self) { height in
                        if height > 0, height != reply.contentHeight { reply.contentHeight = height }
                    }
                }
                ForEach(prompt.choices, id: \.id) { choice in
                    Button { _ = registry.respond(.choice(choice.id), to: prompt) } label: {
                        HStack {
                            Text(choiceLabel(choice, prompt: prompt))
                            Spacer()
                            Image(systemName: choice.id == "accept" ? "checkmark" : "arrow.up.right").font(.caption)
                        }.font(.system(size: 12, weight: .medium)).padding(11).frame(maxWidth: .infinity)
                            .background(.white.opacity(choice.id == "accept" ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10))
                    }.disabled(registry.submitted.contains(prompt.id))
                }
                if prompt.acceptsText {
                    TextField(shell.text("reply"), text: $reply.text)
                    Button(shell.text("send")) { _ = registry.respond(.text(reply.text), to: prompt) }
                        .disabled(registry.submitted.contains(prompt.id) || reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = registry.responseError { Text(shell.text(error)).font(.caption) }
            } else { Text(shell.text("promptUnavailable")) }
            Button(shell.text("back")) { shell.dispatch?(.closePrompt) }
        }.onChange(of: registry.prompt?.id) { _, _ in reply.text = ""; reply.answers = [:] }.frame(width: 520)
    }
    private func choiceLabel(_ choice: PromptChoice, prompt: AgentPrompt) -> String {
        if prompt.sessionID.ownerInstanceID.hasPrefix("codex-hook:") { return shell.text(choice.id) }

        if prompt.sessionID.ownerInstanceID.hasPrefix("codex-daemon:") {
            if ["accept", "acceptForSession", "decline", "cancel"].contains(choice.id) { return shell.text("codex_" + choice.id) }
            if choice.id.hasPrefix("execPolicy:") { return shell.text("codex_execPolicy") + "\n" + choice.text }
            if choice.id.hasPrefix("networkPolicy:allow:") { return shell.text("codex_networkAllow") + "\n" + choice.text }
            if choice.id.hasPrefix("networkPolicy:deny:") { return shell.text("codex_networkDeny") + "\n" + choice.text }
        }
        return choice.text
    }
}
