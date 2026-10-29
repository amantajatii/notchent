import AppKit
import SwiftUI
import IslandCore

struct TerminalFeatureView: View {
    @ObservedObject var store: TerminalSessionStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.sessionIDs, id: \.self) { id in
                            HStack(spacing: 2) {
                                Button { store.selectedID = id } label: {
                                    Text(store.directory(for: id)?.lastPathComponent ?? "Terminal")
                                        .lineLimit(1)
                                        .foregroundStyle(store.selectedID == id ? .white : .gray)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                }
                                .accessibilityLabel("Open terminal in \(store.directory(for: id)?.path ?? "folder")")
                                Button { store.close(id) } label: {
                                    Image(systemName: "xmark").padding(8)
                                }.accessibilityLabel("Close terminal")
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Button { startTerminal() } label: {
                    Label("New terminal", systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 8)
                }
                Button {
                    shell.dispatch?(.inputChanged(false))
                    shell.dispatch?(.hide)
                } label: { Text("Hide").padding(.horizontal, 10).padding(.vertical, 8) }
            }
            .font(.caption)
            .frame(width: 660)
            if let id = store.selectedID {
                OwnedTerminalHost(view: store.view(for: id))
                    .frame(width: 640, height: 340)
                    .padding(10)
                    .background(Color.black)
                    .accessibilityLabel("Terminal session")
            } else {
                Button("Start terminal") { startTerminal() }
                    .frame(width: 660, height: 180)
            }
            if let errorMessage = store.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            if store.sessionIDs.isEmpty { startTerminal() }
        }
        .onDisappear { shell.dispatch?(.inputChanged(false)) }
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
