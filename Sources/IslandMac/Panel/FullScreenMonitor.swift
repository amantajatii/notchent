import AppKit
import IslandCore

/// Uses public WindowServer bounds, not titles, screen capture, or Accessibility grants.
/// A covering borderless/maximized window can conservatively count as full screen.
@MainActor final class FullScreenMonitor {
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var screenBounds: (@MainActor () -> CGRect?)?
    private var onChange: (@MainActor (Bool) -> Void)?
    private(set) var isFullScreen = true

    func start(screenBounds: @escaping @MainActor () -> CGRect?, onChange: @escaping @MainActor (Bool) -> Void) {
        stop()
        self.screenBounds = screenBounds
        self.onChange = onChange
        // Publish conservative initial state before any request source can open a prompt.
        isFullScreen = true
        onChange(true)
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        // Spaces transitions may finish after the workspace notification.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let observed = observe()
        guard observed != isFullScreen else { return }
        isFullScreen = observed
        onChange?(observed)
    }

    private func observe() -> Bool {
        guard let screen = screenBounds?(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        let bounds: [CGRect] = windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  rect.intersects(screen), rect.width > 1, rect.height > 1 else { return nil }
            return rect
        }
        return FullScreenAssessment.isFullScreen(windowBounds: bounds, screen: screen)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }; observers.removeAll()
        screenBounds = nil; onChange = nil
    }
}
