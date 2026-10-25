import AppKit
import Testing
import IslandCore
@testable import IslandMac

@MainActor struct SpotifyLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_LIVE_TESTS"] == "1", "Requires opt-in"))
    func readCurrentSpotifyWithoutChangingPlayback() async throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first,
              let eventClient = SpotifyEventClient(application: app), eventClient.permission() == noErr else {
            Issue.record("Spotify must be running and Automation already authorized before opting in")
            return
        }
        let snapshot = try await NativeSpotifyClient().snapshot()
        #expect(snapshot.availability == .available)
        #expect(snapshot.playback == .playing || snapshot.playback == .paused || snapshot.playback == .stopped)
        // This test deliberately sends no command and does not request consent.
    }
}
