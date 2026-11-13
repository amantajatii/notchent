import AppKit
import SwiftUI

/// Settings live in their own window, opened from the menu bar item, never inside the island.
@MainActor final class SettingsWindowController {
    private let shell: IslandShell
    private var window: NSWindow?

    init(shell: IslandShell) { self.shell = shell }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.title = shell.text("settingsWindowTitle")
        if !window.isVisible { window.center() }
        // An accessory app must activate itself, or the window opens behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = SettingsView(shell: shell, launchAtLogin: shell.launchAtLogin)
            .padding(20)
            .background(Color(white: 0.08))
            .preferredColorScheme(.dark)
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(white: 0.08, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameAutosaveName("NotchentSettings")
        return window
    }
}
