import SwiftUI

struct PromptBannerView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        Button { shell.dispatch?(.openPrompt) } label: {
            Label("\(shell.text("pending")): \(shell.state.pendingCount)", systemImage: "bubble.left.fill")
        }
        .buttonStyle(IslandPillButtonStyle(emphasis: .tinted, tint: IslandDesign.warning))
        .accessibilityLabel(shell.text("openPrompt"))
    }
}
