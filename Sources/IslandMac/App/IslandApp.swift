import AppKit
import SwiftUI
import IslandCore

@MainActor final class IslandShell: ObservableObject {
    @Published var state = IslandState()
    @Published var persistenceError: String?
    @Published var settings: IslandSettings {
        didSet {
            state.settings = settings
            do { try store.save(settings); persistenceError = nil }
            catch { persistenceError = text("saveError") }
            settingsDidChange?()
        }
    }
    let store: SettingsStore
    var settingsDidChange: (() -> Void)?
    var dispatch: ((IslandEvent) -> Void)?
    /// Installed once by a feature owner; keep PTY/session services outside View lifecycle.
    @Published var featureViews: [IslandFeature: AnyView] = [:]
    /// Strong ownership of native terminal views survives switching routes and hiding the panel.
    @Published var retainedNativeViews: [IslandFeature: NSView] = [:]
    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        settings = (try? store.load()) ?? IslandSettings()
        state.settings = settings
    }
    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: settings.language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

@main struct IslandApp: App {
    @NSApplicationDelegateAdaptor(IslandAppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class IslandAppDelegate: NSObject, NSApplicationDelegate {
    let shell = IslandShell()
    private var controller: IslandPanelController!
    private var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = IslandPanelController(shell: shell)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "IslandMac")
        shell.settingsDidChange = { [weak self] in self?.rebuildMenu() }
        rebuildMenu()
        controller.start()
        if CommandLine.arguments.contains("--show") { controller.send(.show(.home)) }
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        for (key, action) in [("open", #selector(open)), ("settings", #selector(settings)), ("quit", #selector(quit))] {
            let item = NSMenuItem(title: shell.text(key), action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
    }
    @objc private func open() { controller.send(.show(.home)) }
    @objc private func settings() { controller.send(.show(.settings)) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller.stop() }
}
