import SwiftUI
import IslandCore

@MainActor private final class ReplyDraft: ObservableObject { @Published var text = "" }

struct PromptView: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    @StateObject private var reply = ReplyDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = registry.prompt {
                Text("PID \(prompt.sessionID.pid)").font(.caption).foregroundStyle(.secondary)
                Text(prompt.text).textSelection(.enabled)
                ForEach(prompt.choices, id: \.id) { choice in
                    Button(choice.text) { _ = registry.respond(.choice(choice.id), to: prompt) }
                }
                if prompt.acceptsText {
                    TextField(shell.text("reply"), text: $reply.text)
                    Button(shell.text("send")) { _ = registry.respond(.text(reply.text), to: prompt) }
                }
                if let error = registry.responseError { Text(shell.text(error)).font(.caption) }
            } else { Text(shell.text("promptUnavailable")) }
            Button(shell.text("back")) { shell.dispatch?(.closePrompt) }
        }.onChange(of: registry.prompt?.id) { _, _ in reply.text = "" }.frame(width: 520).padding(12)
    }
}
