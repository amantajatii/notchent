import AppKit
import Darwin
import IslandCore

struct DiscoveredAgent: Identifiable, Sendable {
    var id: String { "\(pid):\(birth):\(sessionID?.terminalSessionKey ?? "")" }
    let pid: Int32
    let birth: UInt64
    let kind: AgentKind
    let host: HostKind?
    let sessionID: SessionID?
    let ownedTerminal: SessionID?
    let reason: String
    var sourceLabel: String? = nil
    var activity: String? = nil
    var summary: String? = nil
    var completedAt: Date? = nil
}

/// Public kernel metadata only. No argv, environment, terminal contents or private databases.
struct HostSessionDiscovery {
    struct ProcessRecord {
        let pid: Int32
        let parent: Int32
        let birth: UInt64
        let tty: UInt32
        let executable: String
        var uid: uid_t = getuid()
    }
    static func snapshot() -> [ProcessRecord] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 256)
        let size = Int32(pids.count * MemoryLayout<Int32>.stride)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, size) }
        guard actual > 0 else { return [] }
        let owned = pids.prefix(min(Int(actual), pids.count)).compactMap { pid -> ProcessRecord? in
            guard let record = read(pid), record.uid == getuid() else { return nil }
            return record
        }
        return completingAncestors(owned, lookup: read)
    }
    static func snapshotIdentity(_ pid: Int32) -> UInt64? {
        guard let record = read(pid), record.uid == getuid() else { return nil }
        return record.birth
    }
    private static func read(_ pid: Int32) -> ProcessRecord? {
        guard pid > 0 else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var info = proc_bsdinfo()
        let bytes = MemoryLayout<proc_bsdinfo>.stride
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(bytes)) == bytes {
            return ProcessRecord(pid: pid, parent: Int32(info.pbi_ppid), birth: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
                                 tty: info.e_tdev, executable: executable, uid: info.pbi_uid)
        }
        // macOS denies BSD info for root login; public sysctl still exposes its parent.
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var ancestor = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &ancestor, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.stride, ancestor.kp_eproc.e_ucred.cr_uid == 0 else { return nil }
        return ProcessRecord(pid: pid, parent: ancestor.kp_eproc.e_ppid, birth: 0, tty: UInt32.max, executable: executable, uid: 0)
    }
    static func completingAncestors(_ records: [ProcessRecord], lookup: (Int32) -> ProcessRecord?) -> [ProcessRecord] {
        var byPID = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        for record in records {
            var next = record.parent
            var seen = Set<Int32>()
            // Terminal's root-owned login process is ancestry evidence, never an agent candidate.
            while next > 0, seen.insert(next).inserted, seen.count <= 128 {
                if let known = byPID[next] { next = known.parent; continue }
                guard let parent = lookup(next), parent.pid == next,
                      parent.uid == 0 || parent.uid == getuid() else { break }
                byPID[next] = parent
                next = parent.parent
            }
        }
        return Array(byPID.values)
    }
    static func discover(records: [ProcessRecord], owned: [SessionID]) -> [DiscoveredAgent] {
        let byPID = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return records.compactMap { process in
            guard process.uid == getuid(), let kind = kind(for: process.executable) else { return nil }
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
            let evidence = terminal != nil ? "ownedMetadata" : (host != nil ? (process.tty != UInt32.max ? "externalPaneUnknown" : "externalHostOnly") : "hostUnknown")
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
        if path.contains("/ChatGPT.app/") || path.contains("/Codex.app/") { return .codexDesktop }
        if path.contains("/Visual Studio Code.app/") { return .vscode }
        if path.contains("/Orca.app/") { return .orca }
        if path.contains("/Terminal.app/") { return .terminal }
        if path.contains("/iTerm.app/") || path.contains("/iTerm2.app/") { return .iterm2 }
        return nil
    }
}
