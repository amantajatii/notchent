import AppKit
import Combine
import Darwin
import IslandCore
import SwiftTerm

enum TerminalSessionError: Error {
    case invalidDirectory
    case unavailableShell
    case missingProcessIdentity
}

/// Owns each PTY and terminal view independently of SwiftUI's presentation lifetime.
@MainActor final class TerminalSessionStore: ObservableObject, LocalProcessTerminalViewDelegate {
    @Published private(set) var sessionIDs: [SessionID] = []
    @Published var selectedID: SessionID?
    @Published private(set) var lifecycle = TerminalLifecycle()
    @Published var errorMessage: String?

    private let ownerInstanceID = UUID().uuidString
    private var views: [SessionID: LocalProcessTerminalView] = [:]
    private var directories: [SessionID: URL] = [:]

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
        var info = proc_bsdinfo()
        let infoSize = MemoryLayout<proc_bsdinfo>.stride
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(infoSize)) == infoSize else {
            terminal.terminate()
            throw TerminalSessionError.missingProcessIdentity
        }
        let id = SessionID(ownerInstanceID: ownerInstanceID, pid: pid,
                           processStartTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
                           terminalSessionKey: UUID().uuidString)
        views[id] = terminal
        directories[id] = resolved
        sessionIDs.append(id)
        selectedID = id
        lifecycle.open(id)
        return id
    }

    func view(for id: SessionID) -> NSView { views[id] ?? NSView(frame: .zero) }

    func close(_ id: SessionID) {
        guard let terminal = views.removeValue(forKey: id) else { return }
        terminal.processDelegate = nil
        terminal.terminate()
        terminal.removeFromSuperview()
        directories.removeValue(forKey: id)
        sessionIDs.removeAll { $0 == id }
        lifecycle.close(id)
        if selectedID == id { selectedID = sessionIDs.last }
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        guard let id = views.first(where: { $0.value === source })?.key else { return }
        lifecycle.processExited(id)
    }
    func processFailedToStart(source: SwiftTerm.TerminalView, error: LocalProcessError) {
        guard let id = views.first(where: { $0.value === source })?.key else { return }
        lifecycle.processExited(id)
    }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func programStatusChanged(source: SwiftTerm.TerminalView, records: [TerminalProgramStatus]) {}
}
