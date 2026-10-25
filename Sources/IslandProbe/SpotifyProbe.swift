import AppKit
import ApplicationServices
import IslandCore

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
    private static func client() -> SpotifyEventClient? {
        running.flatMap { SpotifyEventClient(application: $0) }
    }
    private static func read(_ client: SpotifyEventClient, property: UInt32, track: Bool = false, state: Bool = false) -> String {
        do {
            let value = try client.read(property, currentTrack: track)
            if state {
                switch value.enumCodeValue {
                case 0x6B505350: return "playing"
                case 0x6B505370: return "paused"
                case 0x6B505353: return "stopped"
                default: return "unavailable; unknown playback enum"
                }
            }
            return value.stringValue?.isEmpty == false ? "available" : "unavailable"
        } catch { return "unavailable (\((error as NSError).code))" }
    }
    static func observe() -> SpotifyObservation {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        var observation = SpotifyObservation(applicationAvailability: installed ? "installed; not running" : "unavailable")
        guard let client = client() else { observation.playbackState = "not-running"; return observation }
        observation.applicationAvailability = "running"
        let preflight = client.permission()
        guard preflight == noErr else {
            let code = preflight
            observation.automation = code == -1743 ? "denied (-1743)" : code == -1744 ? "requires-consent (-1744); no prompt requested" : "unavailable; preflight status \(code); no prompt requested"
            return observation
        }
        observation.automation = "authorized"
        observation.playbackState = read(client, property: 0x70506C53, state: true) // pPlS
        observation.metadataAvailability = read(client, property: 0x706E616D, track: true) // pnam
        observation.artworkAvailability = "URL: " + read(client, property: 0x6155726C, track: true) + "; bytes untested" // aUrl
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
        guard ["play", "pause", "next track", "previous track"].contains(sender.title), let client = Self.client(), client.permission() == noErr else {
            status.stringValue = "Control not sent: Spotify unavailable or Automation not authorized."
            return
        }
        do {
            _ = try client.control(sender.title)
            status.stringValue = "\(sender.title): command returned without error; verify actual playback manually."
        } catch {
            status.stringValue = "Control unavailable/failed: \((error as NSError).code)"
        }
        print(status.stringValue)
    }
}
