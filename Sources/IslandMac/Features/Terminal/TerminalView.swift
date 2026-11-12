import AppKit
import SwiftUI
import IslandCore

struct TerminalFeatureView: View {
    @ObservedObject var store: TerminalSessionStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if let id = store.selectedID {
                OwnedTerminalHost(view: store.view(for: id))
                    .frame(width: 640, height: 340)
                    .padding(10)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous)
                        .strokeBorder(IslandDesign.separator, lineWidth: 1))
                    .accessibilityLabel("Terminal session")
            } else {
                Button("Start terminal") { startTerminal() }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: IslandTint.terminal))
                    .frame(width: 660, height: 180)
            }
            if let errorMessage = store.errorMessage {
                Text(errorMessage).font(IslandDesign.caption).foregroundStyle(IslandDesign.danger)
            }
        }
        .onAppear {
            if store.sessionIDs.isEmpty { startTerminal() }
        }
        .onDisappear { shell.dispatch?(.inputChanged(false)) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.sessionIDs, id: \.self) { id in tab(id) }
                }.padding(3)
            }
            .background(IslandDesign.card, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { startTerminal() } label: { Label("New terminal", systemImage: "plus") }
                .buttonStyle(IslandPillButtonStyle(emphasis: .tinted, tint: IslandTint.terminal))
            Button {
                shell.dispatch?(.inputChanged(false))
                shell.dispatch?(.hide)
            } label: { Text("Hide") }
                .buttonStyle(IslandPillButtonStyle(emphasis: .plain, tint: .white))
        }
        .frame(width: 660)
    }

    private func tab(_ id: SessionID) -> some View {
        let isSelected = store.selectedID == id
        return HStack(spacing: 0) {
            Button { store.selectedID = id } label: {
                Text(store.directory(for: id)?.lastPathComponent ?? "Terminal")
                    .font(IslandDesign.callout.weight(.medium)).lineLimit(1)
                    .foregroundStyle(isSelected ? IslandTint.terminal : IslandDesign.secondary)
                    .padding(.leading, 12).padding(.trailing, 6).frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open terminal in \(store.directory(for: id)?.path ?? "folder")")
            Button { store.close(id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandDesign.secondary).frame(width: 20, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close terminal")
        }
        .background(isSelected ? IslandTint.terminal.opacity(0.2) : Color.clear, in: Capsule())
    }

    private func startTerminal() {
        do {
            _ = try store.create(directory: FileManager.default.homeDirectoryForCurrentUser)
            store.errorMessage = nil
        } catch {
            store.errorMessage = "Could not start terminal: \(error.localizedDescription)"
        }
    }
}

/// Reparenting only changes presentation; the store retains the PTY-backed view.
private struct OwnedTerminalHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        attach(view, to: container)
        return container
    }
    func updateNSView(_ container: NSView, context: Context) { attach(view, to: container) }
    private func attach(_ terminal: NSView, to container: NSView) {
        guard terminal.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        terminal.removeFromSuperview()
        terminal.frame = container.bounds
        terminal.autoresizingMask = [.width, .height]
        container.addSubview(terminal)
    }
}
