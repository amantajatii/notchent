import SwiftUI

/// The "Software Update" row in Settings: version, status, and one action button.
struct UpdateSection: View {
    @ObservedObject var store: UpdateStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        IslandFormSection {
            HStack(spacing: -6) {
                IslandGlyph(symbol: "arrow.triangle.2.circlepath", tint: .gray, size: 26, shape: .squircle)
                    .padding(.leading, IslandDesign.cardPadding)
                IslandFormRow(shell.text("updateTitle"), subtitle: status) { action }
            }
        }
    }

    private var versionText: String {
        "\(shell.text("updateVersion")) \(store.currentVersion?.description ?? "–")"
    }

    private var status: String {
        switch store.phase {
        case .idle: versionText
        case .checking: shell.text("updateChecking")
        case .upToDate: "\(shell.text("updateUpToDate")) · \(versionText)"
        case .available(let release): "\(shell.text("updateAvailable")) \(release.version) · \(versionText)"
        case .installing: shell.text("updateInstalling")
        case .failed(let error): shell.text(error.messageKey)
        }
    }

    @ViewBuilder private var action: some View {
        switch store.phase {
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .available:
            Button(shell.text("updateInstall")) { Task { await store.install() } }
                .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: IslandDesign.accent))
                .disabled(!store.canInstall)
                .help(store.canInstall ? "" : shell.text("updateErrorNotInstalled"))
        default:
            Button(shell.text("updateCheck")) { Task { await store.check() } }
                .buttonStyle(IslandPillButtonStyle())
        }
    }
}
