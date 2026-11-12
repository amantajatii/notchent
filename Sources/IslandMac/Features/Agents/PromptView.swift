import SwiftUI
import IslandCore

// CLT 6.4 does not ship the SwiftUI State macro plugin.
typealias PromptState<Value> = SwiftUI.State<Value>

@MainActor private final class ReplyDraft: ObservableObject {
    @Published var text = ""
    @Published var answers: [String: String] = [:]
    @Published var contentHeight: CGFloat = 80
}

struct PromptView: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    @StateObject private var reply = ReplyDraft()

    var body: some View {
        Group {
            if let prompt = registry.prompt, registry.submitted.contains(prompt.id), registry.responseError == "deliverySent" {
                Text(shell.text("deliverySentCompact"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.75))
                    .lineLimit(1).frame(width: 280)
            } else {
                form
            }
        }.onChange(of: registry.prompt?.id) { _, _ in reply.text = ""; reply.answers = [:] }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let prompt = registry.prompt {
                HStack(spacing: 8) {
                    Label(prompt.sessionID.ownerInstanceID.hasPrefix("codex-") ? "Codex" : "PID \(prompt.sessionID.pid)", systemImage: "terminal")
                    Spacer()
                    if shell.state.pendingCount > 1 {
                        Text("\(shell.state.pendingCount)").monospacedDigit()
                            .accessibilityLabel("\(shell.text("pending")): \(shell.state.pendingCount)")
                    }
                    Button { shell.dispatch?(.closePrompt) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color(white: 0.12), in: Circle())
                    }.accessibilityLabel(shell.text("back")).help(shell.text("back"))
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.7))
                    .help(prompt.sourceLabel ?? "")

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if prompt.questions.isEmpty {
                            ExpandablePromptText(text: prompt.text, shell: shell).id(prompt.id)
                        } else {
                            ForEach(prompt.questions, id: \.id) { question in
                                VStack(alignment: .leading, spacing: 10) {
                                    ExpandablePromptText(text: question.text, shell: shell).id(prompt.id)
                                    ForEach(question.choices, id: \.id) { choice in
                                        Button { reply.answers[question.id] = choice.id } label: {
                                            choiceRow(choice.text, symbol: reply.answers[question.id] == choice.id ? "checkmark.circle.fill" : "circle", selected: reply.answers[question.id] == choice.id)
                                        }.accessibilityAddTraits(reply.answers[question.id] == choice.id ? .isSelected : [])
                                    }
                                    if question.acceptsText {
                                        TextField(shell.text("reply"), text: Binding(get: { reply.answers[question.id] ?? "" }, set: { reply.answers[question.id] = $0 }))
                                            .textFieldStyle(.plain).padding(12)
                                            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
                                            .accessibilityLabel(shell.text("reply"))
                                    }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if height > 0 { reply.contentHeight = height }
                        }
                }.frame(height: min(prompt.questions.isEmpty ? 200 : 320, max(28, reply.contentHeight)))
                    .disabled(registry.submitted.contains(prompt.id))

                ForEach(prompt.choices, id: \.id) { choice in
                    Button { _ = registry.respond(.choice(choice.id), to: prompt) } label: {
                        choiceRow(choiceLabel(choice, prompt: prompt), symbol: choice.id == "accept" ? "checkmark" : "chevron.right", selected: choice.id == "accept")
                    }.disabled(registry.submitted.contains(prompt.id))
                }
                if !prompt.questions.isEmpty {
                    HStack {
                        Spacer()
                        Button { _ = registry.respond(.answers(reply.answers), to: prompt) } label: {
                            Text(shell.text("send")).font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .foregroundStyle(.black).background(.white, in: Capsule())
                        }.disabled(registry.submitted.contains(prompt.id) || !prompt.accepts(answers: reply.answers))
                    }
                }
                if prompt.acceptsText {
                    HStack(spacing: 10) {
                        TextField(shell.text("reply"), text: $reply.text, axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...4)
                            .accessibilityLabel(shell.text("reply"))
                        Button { _ = registry.respond(.text(reply.text), to: prompt) } label: {
                            Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.black).frame(width: 30, height: 30)
                                .background(.white, in: Circle())
                        }.accessibilityLabel(shell.text("send"))
                            .disabled(registry.submitted.contains(prompt.id) || reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(8).padding(.leading, 6)
                        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 18))
                        .disabled(registry.submitted.contains(prompt.id))
                }
                if let error = registry.responseError {
                    Text(shell.text(error)).font(.caption).foregroundStyle(Color(white: 0.75))
                }
            } else {
                Text(shell.text("promptUnavailable"))
                Button(shell.text("back")) { shell.dispatch?(.closePrompt) }
            }
        }.frame(width: 440)
    }

    private func choiceRow(_ text: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }.font(.system(size: 13, weight: .medium)).padding(14)
            .foregroundStyle(selected ? Color.black : .white)
            .background(selected ? Color.white : Color(white: 0.1), in: RoundedRectangle(cornerRadius: 16))
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

struct ExpandablePromptText: View {
    let text: String
    @ObservedObject var shell: IslandShell
    @PromptState var expanded = false
    @PromptState private var fullHeight: CGFloat = 0
    @PromptState private var previewHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).lineLimit(expanded ? nil : 3)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                .background(alignment: .topLeading) {
                    Text(text).fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .accessibilityHidden(true)
                }
            if expanded || fullHeight > previewHeight + 1 {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 5) {
                        Text(shell.text(expanded ? "promptCollapse" : "promptExpand"))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.7))
                        .padding(.vertical, 4)
                }
            }
        }.font(.system(size: 15, weight: .medium))
    }
}
