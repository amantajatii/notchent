import AppKit
import Darwin
import IslandCore

struct DiscoveredAgent: Identifiable, Sendable {
    var id: String { "\(pid):\(birth)" }
    let pid: Int32
    let birth: UInt64
    let kind: AgentKind
    let host: HostKind?
    let sessionID: SessionID?
    let ownedTerminal: SessionID?
    let reason: String
}

/// Public kernel metadata only. No argv, environment, terminal contents or private databases.
struct HostSessionDiscovery {
    struct ProcessRecord {
        let pid: Int32
        let parent: Int32
        let birth: UInt64
        let tty: UInt32
        let executable: String
    }
    static func snapshot() -> [ProcessRecord] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 256)
        let size = Int32(pids.count * MemoryLayout<Int32>.stride)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, size) }
        guard actual > 0 else { return [] }
        return pids.prefix(min(Int(actual), pids.count)).compactMap { pid in
            var info = proc_bsdinfo()
            let bytes = MemoryLayout<proc_bsdinfo>.stride
            guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(bytes)) == bytes,
                  info.pbi_uid == getuid() else { return nil }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { return nil }
            return ProcessRecord(pid: pid, parent: Int32(info.pbi_ppid), birth: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
                                 tty: info.e_tdev, executable: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
    }
    static func discover(records: [ProcessRecord], owned: [SessionID]) -> [DiscoveredAgent] {
        let byPID = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return records.compactMap { process in
            guard let kind = kind(for: process.executable) else { return nil }
            var ancestors: [ProcessRecord] = []
            var next = process.parent
            var seen: Set<Int32> = [process.pid]
            while let parent = byPID[next], seen.insert(next).inserted, ancestors.count < 128 {
                ancestors.append(parent); next = parent.parent
            }
            let terminal = owned.first { id in ancestors.contains { $0.pid == id.pid && $0.birth == id.processStartTime } }
            let host = ancestors.compactMap { host(for: $0.executable) }.first
            let identity = terminal.map { SessionID(ownerInstanceID: $0.ownerInstanceID, pid: process.pid, processStartTime: process.birth, terminalSessionKey: $0.terminalSessionKey) }
            // A TTY and app ancestor identify a host candidate, not its pane's stable identity.
            let evidence = terminal != nil ? "ownedMetadata" : (host != nil && process.tty != UInt32.max ? "externalPaneUnknown" : "hostUnknown")
            return DiscoveredAgent(pid: process.pid, birth: process.birth, kind: kind, host: host, sessionID: identity, ownedTerminal: terminal, reason: evidence)
        }
    }
    static func kind(for path: String) -> AgentKind? {
        switch URL(fileURLWithPath: path).lastPathComponent {
        case "codex": .codex
        case "claude": .claudeCode
        case "agy": .antigravity
        case "omp": .ohMyPi
        default: nil // Script agents running as node cannot be attributed without additional public proof.
        }
    }
    static func host(for path: String) -> HostKind? {
        if path.contains("/Visual Studio Code.app/") { return .vscode }
        if path.contains("/Orca.app/") { return .orca }
        if path.contains("/Terminal.app/") { return .terminal }
        if path.contains("/iTerm.app/") || path.contains("/iTerm2.app/") { return .iterm2 }
        return nil
    }
}
