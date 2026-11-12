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
        VStack(alignment: .leading, spacing: 14) {
            if let prompt = registry.prompt {
                promptHeader(prompt)
                promptBody(prompt)
                choiceButtons(prompt)
                if !prompt.questions.isEmpty { sendRow(prompt) }
                if prompt.acceptsText { replyField(prompt) }
                if let error = registry.responseError {
                    Text(shell.text(error)).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
                }
            } else {
                Text(shell.text("promptUnavailable"))
                Button(shell.text("back")) { shell.dispatch?(.closePrompt) }.buttonStyle(IslandPillButtonStyle())
            }
        }.frame(width: 440)
    }

    private func promptHeader(_ prompt: AgentPrompt) -> some View {
        HStack(spacing: 8) {
            IslandGlyph(symbol: "terminal", tint: IslandTint.neutral, size: 22)
            Text(prompt.sessionID.ownerInstanceID.hasPrefix("codex-") ? "Codex" : "PID \(prompt.sessionID.pid)")
                .font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
            Spacer()
            if shell.state.pendingCount > 1 {
                Text("\(shell.state.pendingCount)").font(IslandDesign.metric).foregroundStyle(IslandDesign.warning).monospacedDigit()
                    .accessibilityLabel("\(shell.text("pending")): \(shell.state.pendingCount)")
            }
            Button { shell.dispatch?(.closePrompt) } label: { Image(systemName: "xmark") }
                .buttonStyle(IslandIconButtonStyle(emphasis: .plain, tint: IslandDesign.primary))
                .accessibilityLabel(shell.text("back")).help(shell.text("back"))
        }.help(prompt.sourceLabel ?? "")
    }

    private func promptBody(_ prompt: AgentPrompt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if prompt.questions.isEmpty {
                    ExpandablePromptText(text: prompt.text, shell: shell).id(prompt.id)
                } else {
                    ForEach(prompt.questions, id: \.id) { question in questionView(question, prompt: prompt) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height > 0 { reply.contentHeight = height }
                }
        }.frame(height: min(prompt.questions.isEmpty ? 200 : 320, max(28, reply.contentHeight)))
            .disabled(registry.submitted.contains(prompt.id))
    }

    private func questionView(_ question: AgentQuestion, prompt: AgentPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ExpandablePromptText(text: question.text, shell: shell).id(prompt.id)
            ForEach(question.choices, id: \.id) { choice in
                let isSelected = reply.answers[question.id] == choice.id
                Button { reply.answers[question.id] = choice.id } label: {
                    ChoiceLabel(text: choice.text, symbol: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(ChoiceCapsuleStyle(emphasis: isSelected ? .filled : .plain, tint: IslandTint.agents))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if question.acceptsText {
                TextField(shell.text("reply"), text: Binding(get: { reply.answers[question.id] ?? "" }, set: { reply.answers[question.id] = $0 }))
                    .textFieldStyle(.plain).padding(.horizontal, 16).frame(height: 36)
                    .background(IslandDesign.fill, in: Capsule())
                    .accessibilityLabel(shell.text("reply"))
            }
        }
    }

    /// Up to three short labels sit side by side like Accept / Decline; anything else stacks.
    private func choiceButtons(_ prompt: AgentPrompt) -> some View {
        let labels = prompt.choices.map { (choice: PromptChoice) -> String in choiceLabel(choice, prompt: prompt) }
        let isCompact = prompt.choices.count <= 3 && labels.allSatisfy { (label: String) -> Bool in
            label.count <= Self.compactLabelLimit && !label.contains("\n")
        }
        let layout = isCompact ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            ForEach(Array(prompt.choices.enumerated()), id: \.element.id) { pair in
                let choice = pair.element
                let style = choiceStyle(choice.id)
                Button { _ = registry.respond(.choice(choice.id), to: prompt) } label: {
                    ChoiceLabel(text: labels[pair.offset], symbol: isCompact ? nil : choiceSymbol(choice.id))
                }
                .buttonStyle(ChoiceCapsuleStyle(emphasis: style.0, tint: style.1))
                .disabled(registry.submitted.contains(prompt.id))
            }
        }
    }

    private func sendRow(_ prompt: AgentPrompt) -> some View {
        HStack {
            Spacer()
            Button(shell.text("send")) { _ = registry.respond(.answers(reply.answers), to: prompt) }
                .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: IslandTint.agents))
                .disabled(registry.submitted.contains(prompt.id) || !prompt.accepts(answers: reply.answers))
        }
    }

    private func replyField(_ prompt: AgentPrompt) -> some View {
        let isEmpty = reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 10) {
            TextField(shell.text("reply"), text: $reply.text, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4)
                .accessibilityLabel(shell.text("reply"))
            Button { _ = registry.respond(.text(reply.text), to: prompt) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(IslandIconButtonStyle(emphasis: isEmpty ? .plain : .filled, tint: IslandTint.agents))
                .accessibilityLabel(shell.text("send"))
                .disabled(registry.submitted.contains(prompt.id) || isEmpty)
        }.padding(4).padding(.leading, 12)
            .background(IslandDesign.fill, in: Capsule())
            .disabled(registry.submitted.contains(prompt.id))
    }

    private static let compactLabelLimit = 18

    /// Accept is the accent, decline / deny is destructive red, everything else is neutral.
    private func choiceStyle(_ id: String) -> (IslandControlEmphasis, Color) {
        if id == "accept" { return (.filled, IslandTint.agents) }
        if id == "decline" || id.hasPrefix("networkPolicy:deny:") { return (.destructive, IslandDesign.danger) }
        return (.plain, IslandDesign.primary)
    }

    private func choiceSymbol(_ id: String) -> String? {
        switch choiceStyle(id).0 {
        case .filled: return "checkmark"
        case .destructive: return "xmark"
        default: return nil
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
                    }.font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
                        .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }.font(.system(size: 16, weight: .semibold))
    }
}

private struct ChoiceLabel: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(text).lineLimit(3).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: symbol == nil ? .center : .leading)
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
        }
    }
}

/// A full-width capsule action, 36pt tall, like Accept / Decline on an incoming-call Live Activity.
private struct ChoiceCapsuleStyle: ButtonStyle {
    let emphasis: IslandControlEmphasis
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let grey = configuration.isPressed ? IslandDesign.fillStrong : IslandDesign.fill
        let foreground: Color = emphasis == .filled ? .white : (emphasis == .destructive ? IslandDesign.danger : IslandDesign.primary)
        let background: Color = emphasis == .filled ? tint : grey
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 36)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
