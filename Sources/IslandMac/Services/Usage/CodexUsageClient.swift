import Foundation

enum CodexUsageDecoder {
    private struct RawWindow: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?

        func window() throws -> UsageWindow {
            guard usedPercent.isFinite, usedPercent >= 0,
                  windowDurationMins.map({ $0 > 0 }) ?? true else { throw UsageError.invalidResponse }
            return UsageWindow(usedPercent: usedPercent, durationMinutes: windowDurationMins,
                               resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) })
        }
    }
    private struct Bucket: Decodable {
        let limitId: String?
        let primary: RawWindow?
        let secondary: RawWindow?
    }
    private struct Response: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?
    }

    /// Decodes `account/rateLimits/read`, preferring the `codex` bucket.
    static func decode(_ data: Data) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let bucket = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits,
              bucket.limitId == nil || bucket.limitId == "codex",
              bucket.primary != nil || bucket.secondary != nil else { throw UsageError.invalidResponse }
        return UsageSnapshot(primary: try bucket.primary?.window(), secondary: try bucket.secondary?.window())
    }
}

/// Reads account limits only; it never opens, resumes, or joins a thread.
struct NativeCodexUsageClient: UsageClient {
    private static let clientInfo = #"{"clientInfo":{"name":"notchent-usage","version":"0.2.0"}}"#
    private static let socketWait: Duration = .milliseconds(50)
    private static let socketAttempts = 100

    let codexHome: URL
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        codexHome = home.appendingPathComponent(".codex")
    }

    func read() async throws -> UsageSnapshot {
        // Prefer the user's running daemon; spawning a private app-server is the fallback.
        if let shared = CodexControlSocket.trustedPath(codexHome: codexHome),
           let usage = try? await query(socketPath: shared) {
            return usage
        }
        return try await readFromPrivateServer()
    }

    private func query(socketPath: URL) async throws -> UsageSnapshot {
        let socket = CodexSocket()
        do {
            try await socket.connect(path: socketPath)
            _ = try await socket.call("initialize", params: Data(Self.clientInfo.utf8))
            try await socket.notify("initialized")
            let data = try await socket.call("account/rateLimits/read", params: Data("{}".utf8))
            await socket.close()
            return try CodexUsageDecoder.decode(data)
        } catch {
            await socket.close()
            throw error
        }
    }

    private func readFromPrivateServer() async throws -> UsageSnapshot {
        guard let executable = CodexExecutable.locate(home: home) else { throw UsageError.notConfigured }
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("nu-" + UUID().uuidString.prefix(8))
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let path = directory.appendingPathComponent("s")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "unix://" + path.path]
        process.environment = CodexExecutable.environment(home: home)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        for _ in 0..<Self.socketAttempts where !files.fileExists(atPath: path.path) {
            guard process.isRunning else { throw CodexSocket.Failure.closed }
            try await Task.sleep(for: Self.socketWait)
        }
        guard files.fileExists(atPath: path.path) else { throw CodexSocket.Failure.timedOut }
        return try await query(socketPath: path)
    }
}

enum CodexControlSocket {
    /// The shared daemon socket, only when it is a socket owned by this user and closed to others.
    static func trustedPath(codexHome: URL) -> URL? {
        let path = codexHome.appendingPathComponent("app-server-control/app-server-control.sock").resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              attributes[.type] as? FileAttributeType == .typeSocket,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else { return nil }
        return path
    }
}

enum CodexExecutable {
    /// GUI apps get a minimal PATH, so common install locations are searched explicitly.
    static func searchDirectories(home: URL, path: String?) -> [String] {
        let known = [".local/bin", ".npm-global/bin", ".bun/bin", ".volta/bin"].map { home.appendingPathComponent($0).path }
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        let inherited = (path ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (known + inherited).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func locate(home: URL, path: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
        searchDirectories(home: home, path: path)
            .map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func environment(home: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchDirectories(home: home, path: environment["PATH"] ?? "/usr/bin:/bin").joined(separator: ":")
        return environment
    }
}
