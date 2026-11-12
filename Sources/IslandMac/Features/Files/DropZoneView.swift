import SwiftUI

struct DropZoneView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 34, weight: .light))
                .foregroundStyle(IslandTint.files)
            Text(shell.text("drop")).font(IslandDesign.largeTitle)
        }
        .frame(width: IslandDesign.contentWidth, height: 112)
        .overlay(
            RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous)
                .strokeBorder(IslandTint.files, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shell.text("drop"))
    }
}
