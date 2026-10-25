import AppKit
import IslandCore

/// Probe-only panel: hovering never activates the app or makes the panel key.
@MainActor
private final class InteractionPanel: NSPanel {
    var allowsInput = false
    override var canBecomeKey: Bool { allowsInput }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelProbe: NSObject, NSApplicationDelegate {
    private var panel: InteractionPanel!
    private var host: NSWindow!
    private var timer: Timer?
    private var screen: NSScreen?
    private let field = NSTextField(string: "")
    private let status = NSTextField(labelWithString: "Hover mode — no keyboard focus")

    static func run() -> Never {
        let app = NSApplication.shared
        let probe = PanelProbe()
        app.setActivationPolicy(.accessory)
        app.delegate = probe
        withExtendedLifetime(probe) { app.run() }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reuse inventory without reading transcripts or changing host sessions.
        let installed = AgentProbe().inventory().filter { $0.capability.hasPrefix("hostInstallation.") }
        print("Panel probe: host inventory entries \(installed.count); no host interaction performed.")
        screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        panel = InteractionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Native Island · panel feasibility"), status,
            NSButton(title: "Enable typing deliberately", target: self, action: #selector(enableInput)), field,
            NSButton(title: "Done / dismiss", target: self, action: #selector(dismiss))
        ])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        field.placeholderString = "Typed text stays here after dismissal"
        panel.contentView = stack
        host = NSWindow(contentRect: CGRect(x: 180, y: 180, width: 640, height: 300), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        host.title = "Island Probe — controlled focus host"
        host.isReleasedWhenClosed = false
        host.collectionBehavior = [.fullScreenPrimary]
        let hostField = NSTextField(string: "Type here to check hover preserves focus")
        let hostStack = NSStackView(views: [
            NSTextField(labelWithString: "Hover at the screen top center. Green title control enters full screen."),
            hostField,
            NSButton(title: "Toggle owned host full screen", target: self, action: #selector(toggleFullScreen)),
            NSButton(title: "Quit probe", target: self, action: #selector(quit))
        ])
        hostStack.orientation = .vertical
        hostStack.spacing = 18
        host.contentView = hostStack
        host.makeKeyAndOrderFront(nil)
        // Explicit launch presents the controlled host; hover never calls activate.
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        print("Panel probe running; no screen-sized or trigger window. Focus/full-screen behavior requires live checks.")
    }

    private func updatePointer() {
        let point = NSEvent.mouseLocation
        if !panel.isVisible {
            screen = NSScreen.screens.first { $0.frame.contains(point) } ?? screen
        }
        guard let screen else { return }
        let menuHeight = max(24, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let trigger = PanelGeometry.triggerRect(screen: screen.frame, menuBarHeight: menuHeight)
        if trigger.contains(point), !panel.isVisible {
            panel.setFrame(PanelGeometry.panelRect(screen: screen.frame, size: CGSize(width: 680, height: 180)), display: true)
            panel.orderFrontRegardless()
            print("Hover shown: key=\(panel.isKeyWindow); frame=\(panel.frame)")
        } else if panel.isVisible, !panel.frame.contains(point), !trigger.contains(point), !panel.allowsInput {
            panel.orderOut(nil)
            print("Pointer exit: panel hidden; text retained in memory, never logged.")
        }
    }

    @objc private func enableInput() {
        panel.allowsInput = true
        panel.makeKey()
        panel.makeFirstResponder(field)
        status.stringValue = "Input mode — Done dismisses; pointer exit keeps editing open"
        print("Deliberate input: key=\(panel.isKeyWindow)")
    }
    @objc private func dismiss() {
        panel.allowsInput = false
        panel.orderOut(nil)
        status.stringValue = "Hover mode — no keyboard focus"
        print("Dismissed; text retained in memory, never logged.")
    }
    @objc private func toggleFullScreen() { host.toggleFullScreen(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
}
