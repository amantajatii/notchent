import AppKit

/// Reads pointer position without installing an invisible event-intercepting window.
@MainActor final class PointerMonitor {
    private var timer: Timer?
    func start(_ update: @escaping @MainActor () -> Void) {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil }

}
