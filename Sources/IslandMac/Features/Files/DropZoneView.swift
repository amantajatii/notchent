import SwiftUI

struct DropZoneView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        Label(shell.text("drop"), systemImage: "tray.and.arrow.down.fill")
            .font(.headline).frame(width: 420, height: 100)
            .accessibilityLabel(shell.text("drop"))
    }
}
