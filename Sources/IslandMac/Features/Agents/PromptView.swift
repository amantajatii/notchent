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
                    .font(Font.system(size: 12, weight: .medium)).foregroundStyle(IslandDesign.secondary)
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
                    HStack(spacing: 6) {
                        IslandGlyph(symbol: "terminal", tint: IslandTint.codex, size: 24)
                        Text(prompt.sessionID.ownerInstanceID.hasPrefix("codex-") ? "Codex" : "PID \(prompt.sessionID.pid)")
                    }
                    Spacer()
                    if shell.state.pendingCount > 1 {
                        Text("\(shell.state.pendingCount)").monospacedDigit()
                            .accessibilityLabel("\(shell.text("pending")): \(shell.state.pendingCount)")
                    }
                    Button { shell.dispatch?(.closePrompt) } label: { Image(systemName: "xmark") }
                        .buttonStyle(IslandIconButtonStyle(emphasis: .plain, tint: IslandDesign.primary))
                        .accessibilityLabel(shell.text("back")).help(shell.text("back"))
                }.font(Font.system(size: 12, weight: .medium)).foregroundStyle(IslandDesign.secondary)
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
                                            choiceRow(choice.text, symbol: reply.answers[question.id] == choice.id ? "checkmark.circle.fill" : "circle",
                                                      emphasis: reply.answers[question.id] == choice.id ? .filled : .plain, tint: IslandTint.agents)
                                        }.buttonStyle(.plain).accessibilityAddTraits(reply.answers[question.id] == choice.id ? .isSelected : [])
                                    }
                                    if question.acceptsText {
                                        TextField(shell.text("reply"), text: Binding(get: { reply.answers[question.id] ?? "" }, set: { reply.answers[question.id] = $0 }))
                                            .textFieldStyle(.plain).padding(12)
                                            .background(IslandDesign.card, in: RoundedRectangle(cornerRadius: IslandDesign.rowRadius, style: .continuous))
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
                        choiceRow(choiceLabel(choice, prompt: prompt), symbol: choiceSymbol(choice.id),
                                  emphasis: choiceStyle(choice.id).0, tint: choiceStyle(choice.id).1)
                    }.buttonStyle(.plain).disabled(registry.submitted.contains(prompt.id))
                }
                if !prompt.questions.isEmpty {
                    HStack {
                        Spacer()
                        Button(shell.text("send")) { _ = registry.respond(.answers(reply.answers), to: prompt) }
                            .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: IslandTint.agents))
                            .disabled(registry.submitted.contains(prompt.id) || !prompt.accepts(answers: reply.answers))
                    }
                }
                if prompt.acceptsText {
                    HStack(spacing: 10) {
                        TextField(shell.text("reply"), text: $reply.text, axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...4)
                            .accessibilityLabel(shell.text("reply"))
                        Button { _ = registry.respond(.text(reply.text), to: prompt) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(IslandIconButtonStyle(emphasis: .filled, tint: IslandTint.agents))
                            .accessibilityLabel(shell.text("send"))
                            .disabled(registry.submitted.contains(prompt.id) || reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(6).padding(.leading, 8)
                        .background(IslandDesign.card, in: RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
                        .disabled(registry.submitted.contains(prompt.id))
                }
                if let error = registry.responseError {
                    Text(shell.text(error)).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
                }
            } else {
                Text(shell.text("promptUnavailable"))
                Button(shell.text("back")) { shell.dispatch?(.closePrompt) }.buttonStyle(IslandPillButtonStyle())
            }
        }.frame(width: 440)
    }

    private func choiceRow(_ text: String, symbol: String, emphasis: IslandControlEmphasis, tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: IslandDesign.rowRadius + 2, style: .continuous)
        let foreground: Color = emphasis == .filled ? .white : (emphasis == .tinted ? tint : IslandDesign.primary)
        let background: Color = emphasis == .filled ? tint : (emphasis == .tinted ? tint.opacity(IslandDesign.tintBackground) : IslandDesign.card)
        return HStack(spacing: 12) {
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }.font(Font.system(size: 13, weight: .medium)).padding(IslandDesign.cardPadding)
            .foregroundStyle(foreground)
            .background(background, in: shape)
            .contentShape(shape)
    }

    /// Accept is green, decline/deny is red, cancel and anything else stays neutral.
    private func choiceStyle(_ id: String) -> (IslandControlEmphasis, Color) {
        switch id {
        // Like an Apple alert: the default action in the accent colour, destructive ones in red.
        case "accept": return (.filled, IslandDesign.accent)
        case "decline": return (.destructive, IslandDesign.danger)
        default:
            if id.hasPrefix("networkPolicy:deny:") { return (.destructive, IslandDesign.danger) }
            return (.plain, IslandDesign.primary)
        }
    }

    private func choiceSymbol(_ id: String) -> String {
        switch choiceStyle(id).1 {
        case IslandDesign.success: return "checkmark"
        case IslandDesign.danger: return "xmark"
        default: return "chevron.right"
        }
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
                    }.font(Font.system(size: 11, weight: .medium)).foregroundStyle(IslandDesign.secondary)
                        .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }.font(.system(size: 15, weight: .medium))
    }
}
