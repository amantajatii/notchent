import Combine
import Foundation

struct UsageWindow: Sendable, Equatable {
    let remainingPercent: Int
    let durationMinutes: Int?
    let resetsAt: Date?

    init(usedPercent: Double, durationMinutes: Int?, resetsAt: Date?) {
        remainingPercent = max(0, min(100, 100 - Int(usedPercent.rounded())))
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }
}

struct UsageSnapshot: Sendable, Equatable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
    /// When the numbers were last reported, if they may be older than this read.
    let observedAt: Date?

    init(primary: UsageWindow?, secondary: UsageWindow?, observedAt: Date? = nil) {
        self.primary = primary; self.secondary = secondary; self.observedAt = observedAt
    }

    var windows: [UsageWindow] { [primary, secondary].compactMap { $0 } }
}

enum UsageError: Error, Equatable {
    /// The data source has not been set up yet (e.g. Claude status line relay not installed).
    case notConfigured
    case invalidResponse
}

protocol UsageClient: Sendable {
    func read() async throws -> UsageSnapshot
}

enum UsageSchedule {
    static let interval: TimeInterval = 300
    static let resetGrace: TimeInterval = 5

    /// Refresh shortly after the next window resets, but at least every `interval`.
    static func nextDelay(after snapshot: UsageSnapshot?, now: Date, interval: TimeInterval = interval) -> TimeInterval {
        let upcoming = snapshot?.windows.compactMap(\.resetsAt).filter { $0 > now }.min()
        guard let upcoming else { return interval }
        return min(interval, upcoming.timeIntervalSince(now) + resetGrace)
    }
}

@MainActor final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var failure: UsageError?
    @Published private(set) var refreshing = false
    private let client: any UsageClient
    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?

    init(client: any UsageClient, interval: TimeInterval = UsageSchedule.interval,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.interval = interval
        self.now = now
    }

    /// A failed read clears the previous numbers rather than presenting them as current.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            snapshot = try await client.read()
            failure = nil
        } catch {
            snapshot = nil
            failure = error as? UsageError ?? .invalidResponse
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.refreshAndPlanNext() else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    private func refreshAndPlanNext() async -> TimeInterval {
        await refresh()
        return UsageSchedule.nextDelay(after: snapshot, now: now(), interval: interval)
    }

    func stop() { task?.cancel(); task = nil }
}
