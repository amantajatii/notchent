import AppKit
import SwiftUI
import IslandCore

struct TerminalFeatureView: View {
    @ObservedObject var store: TerminalSessionStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(store.sessionIDs, id: \.self) { id in
                    Button {
                        store.selectedID = id
                    } label: {
                        Text(store.directory(for: id)?.lastPathComponent ?? "Terminal")
                            .lineLimit(1)
                            .foregroundStyle(store.selectedID == id ? .white : .gray)
                    }
                    .accessibilityLabel("Open terminal in \(store.directory(for: id)?.path ?? "folder")")
                    Button {
                        store.close(id)
                    } label: { Image(systemName: "xmark.circle") }
                    .accessibilityLabel("Close terminal")
                }
                Spacer(minLength: 8)
                Button { chooseDirectory() } label: { Label("New terminal", systemImage: "plus") }
                Button("Hide") {
                    shell.dispatch?(.inputChanged(false))
                    shell.dispatch?(.hide)
                }
            }
            .font(.caption)
            if let id = store.selectedID {
                OwnedTerminalHost(view: store.view(for: id))
                    .frame(width: 660, height: 360)
                    .background(Color.black)
                    .accessibilityLabel("Terminal session")
            } else {
                Button("Choose a folder to start a terminal") { chooseDirectory() }
                    .frame(width: 660, height: 180)
            }
            if let errorMessage = store.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { shell.dispatch?(.inputChanged(false)) }
    }

    private func chooseDirectory() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.prompt = "Open Terminal"
        guard picker.runModal() == .OK, let directory = picker.url else { return }
        do {
            _ = try store.create(directory: directory)
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
