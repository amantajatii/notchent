import Darwin
import IslandCore

/// Reads only process metadata for an explicitly selected PID, never argv or environment.
struct SessionIdentityResolver {
    func processStartTime(pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard count == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    // Owner and pane cannot safely be inferred from PID or project alone.
    func resolve(pid: Int32, verifiedOwner: String?, verifiedTerminalKey: String?) -> SessionID? {
        guard let start = processStartTime(pid: pid) else { return nil }
        return SessionID.resolve(ownerInstanceID: verifiedOwner, pid: pid, processStartTime: start, terminalSessionKey: verifiedTerminalKey)
    }
}
