import SwiftUI

struct DropZoneView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 28, weight: .light))
                .frame(width: 56, height: 56).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            Text(shell.text("drop")).font(.system(size: 17, weight: .medium))
        }.frame(width: 520, height: 112)
            .accessibilityLabel(shell.text("drop"))
    }
}
