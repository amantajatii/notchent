import SwiftUI
struct PromptBannerView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        Button { shell.dispatch?(.openPrompt) } label: {
            Label("\(shell.text("pending")): \(shell.state.pendingCount)", systemImage: "bubble.left.fill")
                .font(.caption.bold()).padding(8)
        }.accessibilityLabel(shell.text("openPrompt"))
    }
}
