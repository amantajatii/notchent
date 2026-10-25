import AppKit
import IslandCore

@MainActor final class NativeSpotifyClient: SpotifyConsentClient {
    private func current() -> SpotifyEventClient? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            .first.flatMap(SpotifyEventClient.init(application:))
    }
    private func checked() throws -> SpotifyEventClient {
        guard let client = current() else { throw SpotifyFailure.unavailable }
        try Self.check(client.permission())
        return client
    }
    static func check(_ status: OSStatus) throws {
        switch status {
        case noErr: return
        case -1744: throw SpotifyFailure.requiresConsent
        case -1743: throw SpotifyFailure.denied
        case -600: throw SpotifyFailure.unavailable
        default: throw SpotifyFailure.commandFailed(Int(status))
        }
    }
    private func read(_ client: SpotifyEventClient, _ code: UInt32, track: Bool = false) throws -> NSAppleEventDescriptor {
        do { return try client.read(code, currentTrack: track) }
        catch { try Self.check(OSStatus((error as NSError).code)); throw error }
    }
    func snapshot() async throws -> SpotifySnapshot {
        guard let client = current() else { return SpotifySnapshot(availability: .unavailable) }
        let status = client.permission()
        if status == -1744 { return SpotifySnapshot(availability: .requiresConsent) }
        if status == -1743 { return SpotifySnapshot(availability: .denied) }
        try Self.check(status)
        let state = try read(client, 0x70506C53).enumCodeValue // pPlS
        let playback: SpotifyPlayback
        switch state {
        case 0x6B505350: playback = .playing
        case 0x6B505370: playback = .paused
        case 0x6B505353: playback = .stopped
        default: playback = .unknown
        }
        guard playback == .playing || playback == .paused else {
            return SpotifySnapshot(availability: .available, playback: playback)
        }
        let title = try read(client, 0x706E616D, track: true).stringValue // pnam
        let artist = try read(client, 0x70417274, track: true).stringValue // pArt
        let art = try read(client, 0x6155726C, track: true).stringValue // aUrl
        let position = try? read(client, 0x70506F73).doubleValue // pPos
        let duration = try? read(client, 0x70447572, track: true).doubleValue // pDur
        return SpotifySnapshot(availability: .available, playback: playback,
                               title: title?.isEmpty == false ? title : nil,
                               artist: artist?.isEmpty == false ? artist : nil,
                               artworkURL: art.flatMap(URL.init(string:)), position: position, duration: duration)
    }
    func perform(_ command: SpotifyCommand) async throws {
        let client = try checked()
        let name: String
        switch command {
        case .toggle:
            let state = try read(client, 0x70506C53).enumCodeValue
            name = state == 0x6B505350 ? "pause" : "play"
        case .previous: name = "previous track"
        case .next: name = "next track"
        }
        do { _ = try client.control(name) }
        catch { try Self.check(OSStatus((error as NSError).code)); throw error }
    }
    func requestConsent() async throws {
        guard let client = current() else { throw SpotifyFailure.unavailable }
        try Self.check(client.requestPermission())
    }
}
