import AppKit
import Combine
import Foundation

/// Drives "Check for Updates" in Settings: checks GitHub, then installs and restarts on request.
@MainActor final class UpdateStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing(ReleaseInfo)
        case failed(UpdateError)
    }

    static let checkInterval: TimeInterval = 86_400

    @Published private(set) var phase: Phase = .idle
    let currentVersion: AppVersion?
    private let feed: any ReleaseFeed
    private let installer: any UpdateInstalling
    private let bundleURL: URL
    private let quit: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(feed: any ReleaseFeed = GitHubReleaseFeed(), installer: any UpdateInstalling = NativeUpdateInstaller(),
         currentVersion: AppVersion? = .current, bundleURL: URL = Bundle.main.bundleURL,
         quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.feed = feed
        self.installer = installer
        self.currentVersion = currentVersion
        self.bundleURL = bundleURL
        self.quit = quit
    }

    /// False for development builds (e.g. `.build/apps`), which must be installed first.
    var canInstall: Bool { installer.canInstall(at: bundleURL) }

    var isBusy: Bool {
        switch phase {
        case .checking, .installing: true
        default: false
        }
    }

    func check() async {
        guard !isBusy else { return }
        phase = .checking
        do {
            let release = try await feed.latest()
            if let current = currentVersion, release.version <= current { phase = .upToDate }
            else { phase = .available(release) }
        } catch {
            phase = .failed(error as? UpdateError ?? .network)
        }
    }

    func install() async {
        guard case .available(let release) = phase else { return }
        guard canInstall else { phase = .failed(.notInstalled); return }
        phase = .installing(release)
        do {
            try await installer.stage(release, replacing: bundleURL)
            // The helper swaps the bundle once this process has exited, then relaunches it.
            quit()
        } catch {
            phase = .failed(error as? UpdateError ?? .installFailed)
        }
    }

    /// Checks at launch and once a day; installing always waits for the user.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                do { try await Task.sleep(for: .seconds(Self.checkInterval)) } catch { return }
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
}
