import AppKit

/// Reads pointer position without installing an invisible event-intercepting window.
@MainActor final class PointerMonitor {
    private var timer: Timer?
    func start(_ update: @escaping @MainActor () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { update() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

}
