import Foundation
import Testing
@testable import IslandCore

@MainActor private final class FakeSpotifyClient: SpotifyClient {
    var result = SpotifySnapshot(availability: .unavailable)
    var failure: SpotifyFailure?
    var commands: [SpotifyCommand] = []
    func snapshot() async throws -> SpotifySnapshot { result }
    func perform(_ command: SpotifyCommand) async throws {
        commands.append(command)
        if let failure { throw failure }
    }
}

@MainActor struct SpotifyStateTests {
    @Test func unavailableAndDeniedHaveNoSong() async {
        let client = FakeSpotifyClient()
        let store = SpotifyStore(client: client)
        await store.refresh()
        #expect(store.snapshot.availability == .unavailable)
        #expect(store.snapshot.title == nil)
        client.result = SpotifySnapshot(availability: .requiresConsent, title: "Should not surface")
        await store.refresh()
        #expect(store.snapshot.availability == .requiresConsent)
        #expect(store.snapshot.title == nil)
        client.result = SpotifySnapshot(availability: .denied)
        await store.refresh()
        #expect(store.snapshot.availability == .denied)
        #expect(store.snapshot.title == nil)
    }

    @Test func playingAndPausedShareLatestSnapshot() async {
        let client = FakeSpotifyClient()
        let store = SpotifyStore(client: client)
        client.result = SpotifySnapshot(availability: .available, playback: .playing, title: "Live", artist: "Artist")
        await store.refresh()
        #expect(store.snapshot.playback == .playing)
        #expect(store.snapshot.title == "Live")
        client.result.playback = .paused
        await store.refresh()
        #expect(store.snapshot.playback == .paused)
        #expect(store.snapshot.title == "Live")
    }

    @Test func commandFailureDoesNotClaimPlaybackChanged() async {
        let client = FakeSpotifyClient()
        client.result = SpotifySnapshot(availability: .available, playback: .paused, title: "Live")
        let store = SpotifyStore(client: client)
        await store.refresh()
        client.failure = .denied
        await store.perform(.toggle)
        #expect(client.commands == [.toggle])
        #expect(store.snapshot.availability == .denied)
        #expect(store.snapshot.playback == .unknown)
        #expect(store.snapshot.title == nil)
    }

    @Test func genericCommandFailureKeepsObservedStateAndShowsError() async {
        let client = FakeSpotifyClient()
        client.result = SpotifySnapshot(availability: .available, playback: .playing, title: "Observed")
        let store = SpotifyStore(client: client)
        await store.refresh()
        client.failure = .commandFailed(-1708)
        await store.perform(.next)
        #expect(store.snapshot.playback == .playing)
        #expect(store.snapshot.title == "Observed")
        #expect(store.commandError == .commandFailed(-1708))
    }
}
