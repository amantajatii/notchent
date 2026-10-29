import Foundation
import Darwin

public struct CodexHookEnvelope: Codable, Sendable, Equatable {
    public let id: UUID
    public let pid: Int32
    public let birth: UInt64
    public let createdAt: Date
    public let input: Data
    public init(id: UUID = UUID(), pid: Int32, birth: UInt64, createdAt: Date = Date(), input: Data) {
        self.id = id; self.pid = pid; self.birth = birth; self.createdAt = createdAt; self.input = input
    }
}
public struct CodexHookHost: Codable {
    public let pid: Int32
    public let birth: UInt64
    public init(pid: Int32, birth: UInt64) { self.pid = pid; self.birth = birth }
}

/// A private, bounded local mailbox. No request text is logged or sent over a network.
public struct CodexHookMailbox: Sendable {
    public let root: URL
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/IslandMac/HookRequests")) { self.root = root }
    public static func birth(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size, info.pbi_uid == getuid() else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }
    public func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard secureDirectory(root) else { throw CocoaError(.fileReadNoPermission) }
    }
    public func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func secureDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == getuid() && info.st_mode & 0o077 == 0
    }
    public func read(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size <= 131_072 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size) + 1)
        let count = Darwin.read(fd, &bytes, bytes.count)
        guard count == info.st_size else { return nil }
        return Data(bytes.prefix(count))
    }
    public func write(_ data: Data, to url: URL) throws {
        guard data.count <= 131_072, secureDirectory(url.deletingLastPathComponent()) else { throw CocoaError(.fileWriteNoPermission) }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd); unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += count
            }
        }
        // Publish a complete file atomically, without replacing an earlier answer.
        guard link(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteFileExists) }
    }
    public static func decision(event: String, choice: String) throws -> Data {
        if choice == "hookContinue" { return Data("{}".utf8) }
        guard event == "PermissionRequest", ["hookAllow", "hookDeny"].contains(choice) else { throw AgentRoutingError.invalidResponse }
        return try JSONSerialization.data(withJSONObject: ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": choice == "hookAllow" ? "allow" : "deny"]]])
    }
}
