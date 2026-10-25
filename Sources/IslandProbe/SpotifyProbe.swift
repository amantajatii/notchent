import AppKit
import ApplicationServices

struct SpotifyObservation: Codable {
    var applicationAvailability: String
    var playbackState: String = "untested"
    var metadataAvailability: String = "untested"
    // URL availability is independent of downloading/decoding artwork bytes.
    var artworkAvailability: String = "untested"
    var supportedControls = ["play": "dictionary-supported; live untested", "pause": "dictionary-supported; live untested", "next track": "dictionary-supported; live untested", "previous track": "dictionary-supported; live untested"]
    var automation: String = "untested"
}

@MainActor
final class SpotifyProbe: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Read-only observation pending")
    private static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first
    }
    /// Preflight never asks macOS to display or approve an Automation prompt.
    private static func permission() -> OSStatus? {
        guard let app = running else { return nil }
        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
    }
    private static func query(_ expression: String, command: Bool = false) -> (String?, Int?) {
        guard running != nil else { return (nil, -600) }
        // The running guard in both host and script avoids intentionally launching Spotify.
        let source = """
        if application id "com.spotify.client" is not running then return "not-running"
        tell application id "com.spotify.client"
            \(command ? expression : "return " + expression)
        end tell
        """
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (value?.stringValue, (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
    }
    static func observe() -> SpotifyObservation {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        var observation = SpotifyObservation(applicationAvailability: installed ? "installed; not running" : "unavailable")
        guard running != nil else { observation.playbackState = "not-running"; return observation }
        observation.applicationAvailability = "running"
        let preflight = permission()
        guard preflight == noErr else {
            let code = preflight ?? -600
            observation.automation = code == -1743 ? "denied (-1743)" : code == -1744 ? "requires-consent (-1744); no prompt requested" : "unavailable; preflight status \(code); no prompt requested"
            return observation
        }
        observation.automation = "authorized"
        let state = query("player state as text")
        observation.playbackState = state.1 == nil ? state.0 ?? "unavailable" : "unavailable (\(state.1!))"
        let metadata = query("(name of current track is not \"\") as text")
        observation.metadataAvailability = metadata.1 == nil ? metadata.0 ?? "unavailable" : "unavailable (\(metadata.1!))"
        let artwork = query("(artwork url of current track is not \"\") as text")
        observation.artworkAvailability = artwork.1 == nil ? "URL present: \(artwork.0 ?? "unknown"); bytes untested" : "unavailable (\(artwork.1!))"
        return observation
    }
    static func printObservation() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(observe()) { print(String(decoding: data, as: UTF8.self)) }
    }
    static func run() -> Never {
        let app = NSApplication.shared
        let probe = SpotifyProbe()
        app.setActivationPolicy(.regular)
        app.delegate = probe
        withExtendedLifetime(probe) { app.run() }
        exit(0)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let stack = NSStackView(views: [status, NSButton(title: "Refresh read-only", target: self, action: #selector(refresh))])
        for command in ["play", "pause", "next track", "previous track"] {
            let button = NSButton(title: command, target: self, action: #selector(control(_:)))
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "Controls change playback only after your click. Automation is preflighted without prompting; grant permission manually in System Settings if needed."))
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window = NSWindow(contentRect: CGRect(x: 220, y: 220, width: 660, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Island Probe — Spotify"
        window.contentView = stack
        window.makeKeyAndOrderFront(nil)
        refresh()
    }
    @objc private func refresh() {
        let observation = Self.observe()
        status.stringValue = "\(observation.applicationAvailability) | \(observation.automation) | state: \(observation.playbackState) | metadata: \(observation.metadataAvailability) | artwork: \(observation.artworkAvailability)"
        Self.printObservation()
    }
    @objc private func control(_ sender: NSButton) {
        guard ["play", "pause", "next track", "previous track"].contains(sender.title), Self.permission() == noErr else {
            status.stringValue = "Control not sent: Spotify unavailable or Automation not authorized."
            return
        }
        let result = Self.query(sender.title + "\nreturn \"command completed\"", command: true)
        status.stringValue = result.1 == nil ? "\(sender.title): command returned without error; verify actual playback manually." : "Control failed: \(result.1!)"
        print(status.stringValue)
    }
}
