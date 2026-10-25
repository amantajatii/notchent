import Foundation
import Combine

public enum SpotifyAvailability: Sendable, Equatable { case unavailable, requiresConsent, denied, available }
public enum SpotifyPlayback: Sendable, Equatable { case unknown, stopped, paused, playing }
public enum SpotifyCommand: Sendable, Equatable { case toggle, previous, next }
public enum SpotifyFailure: Error, Sendable, Equatable { case unavailable, requiresConsent, denied, commandFailed(Int) }

public struct SpotifySnapshot: Sendable, Equatable {
    public var availability: SpotifyAvailability
    public var playback: SpotifyPlayback
    public var title: String?
    public var artist: String?
    public var artworkURL: URL?
    public var position: TimeInterval?
    public var duration: TimeInterval?

    public init(availability: SpotifyAvailability, playback: SpotifyPlayback = .unknown, title: String? = nil,
                artist: String? = nil, artworkURL: URL? = nil, position: TimeInterval? = nil, duration: TimeInterval? = nil) {
        self.availability = availability
        self.playback = playback
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.position = position
        self.duration = duration
    }
}

@MainActor public protocol SpotifyClient {
    func snapshot() async throws -> SpotifySnapshot
    func perform(_ command: SpotifyCommand) async throws
}

@MainActor public protocol SpotifyConsentClient: SpotifyClient {
    func requestConsent() async throws
}

@MainActor public final class SpotifyStore: ObservableObject {
    @Published public private(set) var snapshot = SpotifySnapshot(availability: .unavailable)
    @Published public private(set) var commandError: SpotifyFailure?
    private let client: any SpotifyClient
    private var polling: Task<Void, Never>?

    public init(client: any SpotifyClient) { self.client = client }

    public func refresh() async {
        do {
            let updated = try await client.snapshot()
            snapshot = updated.availability == .available ? updated : SpotifySnapshot(availability: updated.availability)
        } catch { snapshot = SpotifySnapshot(availability: Self.availability(for: error)) }
    }

    public func perform(_ command: SpotifyCommand) async {
        guard snapshot.availability == .available else { return }
        do {
            try await client.perform(command)
            commandError = nil
            await refresh()
        } catch {
            let failure = (error as? SpotifyFailure) ?? .commandFailed((error as NSError).code)
            commandError = failure
            if failure == .denied || failure == .requiresConsent || failure == .unavailable {
                snapshot = SpotifySnapshot(availability: Self.availability(for: failure))
            }
        }
    }

    public func connect() async {
        guard let consentClient = client as? any SpotifyConsentClient else { return }
        do { try await consentClient.requestConsent(); commandError = nil; await refresh() }
        catch { snapshot = SpotifySnapshot(availability: Self.availability(for: error)) }
    }

    /// Poll only while Home or Music is visible. Hiding the panel cancels the next refresh.
    public func setActive(_ active: Bool) {
        if !active { polling?.cancel(); polling = nil; return }
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private static func availability(for error: Error) -> SpotifyAvailability {
        switch error as? SpotifyFailure {
        case .denied: .denied
        case .requiresConsent: .requiresConsent
        default: .unavailable
        }
    }
}
