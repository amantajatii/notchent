import AppKit
import Combine
import Darwin
import IslandCore
import SwiftTerm

enum TerminalSessionError: Error {
    case invalidDirectory
    case unavailableShell
    case missingProcessIdentity
    case missingPTYIdentity
}

/// Owns each PTY and terminal view independently of SwiftUI's presentation lifetime.
@MainActor final class TerminalSessionStore: ObservableObject, LocalProcessTerminalViewDelegate {
    @Published private(set) var sessionIDs: [SessionID] = []
    @Published var selectedID: SessionID?
    @Published private(set) var lifecycle = TerminalLifecycle()
    @Published var errorMessage: String?

    private let ownerInstanceID = UUID().uuidString
    private var views: [SessionID: LocalProcessTerminalView] = [:]
    private var closingViews: [SessionID: LocalProcessTerminalView] = [:]
    private var escalationTasks: [SessionID: Task<Void, Never>] = [:]
    private var directories: [SessionID: URL] = [:]
    private var ptyIdentities: [SessionID: (device: dev_t, inode: ino_t, rawDevice: dev_t)] = [:]
    /// Injectable for the PID-reuse regression; production reads kernel birth time.
    var processBirthTime: (Int32) -> UInt64? = TerminalSessionStore.kernelBirthTime

    nonisolated private static func kernelBirthTime(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    var hasRunningOwnedSessions: Bool { lifecycle.hasRunningOwnedSessions }
    func directory(for id: SessionID) -> URL? { directories[id] }
    func isRunning(_ id: SessionID) -> Bool { lifecycle.isRunning(id) }

    func create(directory: URL) throws -> SessionID {
        let resolved = directory.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard resolved.isFileURL, FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TerminalSessionError.invalidDirectory
        }
        let shell = getpwuid(getuid()).map { String(cString: $0.pointee.pw_shell) } ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { throw TerminalSessionError.unavailableShell }

        let terminal = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 660, height: 360))
        terminal.processDelegate = self
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        // Preserve the user's PATH, locale and CLI credentials in the child without logging them.
        let entries = environment.map { "\($0.key)=\($0.value)" }
        switch terminal.process.startProcessChecked(executable: shell, args: ["-l"], environment: entries, currentDirectory: resolved.path) {
        case .success: break
        case .failure(let error): throw error
        }
        let pid = terminal.process.shellPid
        guard let birth = processBirthTime(pid) else {
            terminal.terminate()
            throw TerminalSessionError.missingProcessIdentity
        }
        let id = SessionID(ownerInstanceID: ownerInstanceID, pid: pid,
                           processStartTime: birth,
                           terminalSessionKey: UUID().uuidString)
        var ptyStat = stat()
        guard terminal.process.childfd >= 0, fstat(terminal.process.childfd, &ptyStat) == 0 else {
            terminal.terminate()
            throw TerminalSessionError.missingPTYIdentity
        }
        views[id] = terminal
        ptyIdentities[id] = (ptyStat.st_dev, ptyStat.st_ino, ptyStat.st_rdev)
        directories[id] = resolved
        sessionIDs.append(id)
        selectedID = id
        lifecycle.open(id)
        return id
    }

    func view(for id: SessionID) -> NSView { views[id] ?? NSView(frame: .zero) }

    func close(_ id: SessionID) {
        guard let terminal = views.removeValue(forKey: id) else { return }
        let wasRunning = terminal.process.running
        lifecycle.close(id)
        if wasRunning { closingViews[id] = terminal }
        terminal.terminate()
        terminal.removeFromSuperview()
        directories.removeValue(forKey: id)
        sessionIDs.removeAll { $0 == id }
        if selectedID == id { selectedID = sessionIDs.last }
        if wasRunning {
            escalationTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                for _ in 0..<30 {
                    guard !Task.isCancelled, let self, self.lifecycle.isRunning(id) else { return }
                    self.escalateIfStillOwned(id)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        } else {
            terminal.processDelegate = nil
            ptyIdentities.removeValue(forKey: id)
            lifecycle.processExited(id)
        }
    }

    /// TIOCSIG sends SIGKILL through this owned PTY to its foreground process group.
    /// Rechecking birth time rejects a reused shell PID; the PTY descriptor itself
    /// bounds the signal target even if the shell exits between the check and ioctl.
    func escalateIfStillOwned(_ id: SessionID) {
        guard let terminal = closingViews[id], terminal.process.running,
              terminal.process.shellPid == id.pid,
              processBirthTime(id.pid) == id.processStartTime else { return }
        let currentFD = terminal.process.childfd
        guard currentFD >= 0, let identity = ptyIdentities[id] else { return }
        // Hold a separate descriptor so SwiftTerm cannot close and recycle the
        // integer between validation and TIOCSIG.
        let fd = dup(currentFD)
        guard fd >= 0 else { return }
        defer { _ = Darwin.close(fd) }
        var currentStat = stat()
        guard fstat(fd, &currentStat) == 0,
              currentStat.st_dev == identity.device, currentStat.st_ino == identity.inode,
              currentStat.st_rdev == identity.rawDevice else { return }
        if processBirthTime(id.pid) == id.processStartTime {
            let foregroundGroup = tcgetpgrp(fd)
            if foregroundGroup > 0, foregroundGroup != getpgrp(), getsid(foregroundGroup) == id.pid,
               processBirthTime(id.pid) == id.processStartTime {
                _ = Darwin.ioctl(fd, TIOCSIG, SIGKILL)
            }
        }
    }

    func closeAllAndWait() async -> Bool {
        for id in sessionIDs { close(id) }
        for _ in 0..<60 {
            if !hasRunningOwnedSessions { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !hasRunningOwnedSessions
    }

    private func finish(_ id: SessionID) {
        lifecycle.processExited(id)
        escalationTasks.removeValue(forKey: id)?.cancel()
        ptyIdentities.removeValue(forKey: id)
        if let closed = closingViews.removeValue(forKey: id) { closed.processDelegate = nil }
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        guard let id = views.first(where: { $0.value === source })?.key ?? closingViews.first(where: { $0.value === source })?.key else { return }
        finish(id)
    }
    func processFailedToStart(source: SwiftTerm.TerminalView, error: LocalProcessError) {
        guard let id = views.first(where: { $0.value === source })?.key ?? closingViews.first(where: { $0.value === source })?.key else { return }
        finish(id)
    }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func programStatusChanged(source: SwiftTerm.TerminalView, records: [TerminalProgramStatus]) {}
}
