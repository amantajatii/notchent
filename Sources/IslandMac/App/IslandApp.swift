import AppKit
import SwiftUI
import IslandCore

@MainActor final class IslandShell: ObservableObject {
    @Published var state = IslandState()
    /// Every change replays the content entrance, so the shape moves first and content follows.
    @Published var presentedMode: IslandMode = .hidden {
        willSet { if newValue != presentedMode { surface.reveal = ContentReveal.between(presentedMode, newValue, after: surface.reveal) } }
    }
    let surface = IslandSurfaceState()
    var contentSizeDidChange: ((IslandMode, CGSize) -> Void)?
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
    private let localizations: Bundle
    var settingsDidChange: (() -> Void)?
    var dispatch: ((IslandEvent) -> Void)?
    /// Installed once by a feature owner; keep PTY/session services outside View lifecycle.
    @Published var featureViews: [IslandFeature: AnyView] = [:]
    @Published var fileSummaryView: AnyView?
    /// Strong ownership of native terminal views survives switching routes and hiding the panel.
    @Published var retainedNativeViews: [IslandFeature: NSView] = [:]
    let spotify = SpotifyStore(client: NativeSpotifyClient())
    let artwork = ArtworkPaletteStore()
    let files = NativeFileAccess()
    let terminals = TerminalSessionStore()
    let agents = AgentRegistry()
    let codexUsage = UsageStore(client: NativeCodexUsageClient())
    /// Reads a local file written by the Claude status line relay, so it can poll often.
    let claudeUsage = UsageStore(client: NativeClaudeUsageClient(), interval: 30)
    let launchAtLogin = LaunchAtLoginStore()
    let updates = UpdateStore()
    init(store: SettingsStore = SettingsStore(), localizations: Bundle = .main) {
        self.store = store
        self.localizations = localizations
        settings = (try? store.load()) ?? IslandSettings()
        state.settings = settings
        artwork.follow(spotify)
    }
    func text(_ key: String) -> String {
        guard let path = localizations.path(forResource: settings.language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

@main struct IslandApp: App {
    @NSApplicationDelegateAdaptor(IslandAppDelegate.self) var delegate
    var body: some Scene {
        // Settings open in SettingsWindowController from the menu bar item; this scene is never shown.
        Settings { EmptyView() }
    }
}

@MainActor final class IslandAppDelegate: NSObject, NSApplicationDelegate {
    let shell = IslandShell()
    private var controller: IslandPanelController!
    private lazy var settingsWindow = SettingsWindowController(shell: shell)
    private var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = IslandPanelController(shell: shell)
        shell.featureViews[.files] = AnyView(FileShelfView(shell: shell, access: shell.files))
        shell.featureViews[.terminal] = AnyView(TerminalFeatureView(store: shell.terminals, shell: shell))
        shell.featureViews[.agents] = AnyView(AgentListView(registry: shell.agents, shell: shell))
        shell.agents.completionChanged = { [weak shell] in shell?.dispatch?(.agentCompleted) }
        shell.agents.start(terminals: shell.terminals) { [weak shell] count in shell?.dispatch?(.pendingChanged(count)) }
        shell.codexUsage.start()
        shell.claudeUsage.start()
        shell.updates.start()
        shell.fileSummaryView = AnyView(FileShelfSummary(shell: shell, access: shell.files))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notchent")
        shell.settingsDidChange = { [weak self] in self?.rebuildMenu() }
        rebuildMenu()
        controller.start()
        if CommandLine.arguments.contains("--show") {
            controller.inspectionPinned = true
            controller.send(.show(.home))
        } else {
            controller.send(.reveal(.home))
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.send(.reveal(.home))
        return false
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        for (key, action, shortcut) in [("open", #selector(open), ""), ("settings", #selector(settings), ","), ("quit", #selector(quit), "q")] {
            let title = key == "settings" ? shell.text(key) + "…" : shell.text(key)
            let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
            item.target = self; menu.addItem(item)
            if key == "settings" { menu.addItem(.separator()) }
        }
        statusItem.menu = menu
    }
    @objc private func open() { controller.send(.reveal(.home)) }
    @objc private func settings() { settingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shell.terminals.hasRunningOwnedSessions {
            let alert = NSAlert()
            alert.messageText = "Quit Notchent?"
            alert.informativeText = "Running terminals created in Notchent will be closed."
            alert.addButton(withTitle: "Quit and Close Terminals")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            Task { @MainActor in
                let stopped = await shell.terminals.closeAllAndWait()
                sender.reply(toApplicationShouldTerminate: stopped)
            }
            return .terminateLater
        }
        for id in shell.terminals.sessionIDs { shell.terminals.close(id) }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { shell.codexUsage.stop(); shell.claudeUsage.stop(); shell.updates.stop(); shell.agents.stop(); controller.stop() }
}
