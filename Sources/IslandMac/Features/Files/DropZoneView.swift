import SwiftUI

struct DropZoneView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .light))
                .foregroundStyle(IslandTint.files)
            Text(shell.text("drop")).font(IslandDesign.largeTitle)
        }
        .frame(width: IslandDesign.contentWidth, height: 112)
        .background(IslandTint.files.opacity(0.08), in: RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous)
                .strokeBorder(IslandTint.files.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shell.text("drop"))
    }
}
