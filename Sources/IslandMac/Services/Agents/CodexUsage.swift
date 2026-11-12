import Combine
import Foundation

struct CodexUsageSnapshot: Sendable {
    struct Window: Sendable {
        let remainingPercent: Int
        let windowDurationMins: Int?
        let resetsAt: Date?
    }
    let primary: Window?
    let secondary: Window?

    static func decode(_ data: Data) throws -> Self {
        struct RawWindow: Decodable {
            let usedPercent: Int
            let windowDurationMins: Int?
            let resetsAt: Double?
            func window() throws -> Window {
                guard usedPercent >= 0, windowDurationMins.map({ $0 > 0 }) ?? true else { throw CocoaError(.coderReadCorrupt) }
                return Window(remainingPercent: max(0, 100 - usedPercent), windowDurationMins: windowDurationMins,
                              resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) })
            }
        }
        struct Bucket: Decodable {
            let limitId: String?
            let primary: RawWindow?
            let secondary: RawWindow?
        }
        struct Response: Decodable {
            let rateLimits: Bucket?
            let rateLimitsByLimitId: [String: Bucket]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let bucket = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits,
              bucket.limitId == nil || bucket.limitId == "codex",
              bucket.primary != nil || bucket.secondary != nil else { throw CocoaError(.coderReadCorrupt) }
        return try Self(primary: bucket.primary?.window(), secondary: bucket.secondary?.window())
    }
}

protocol CodexUsageClient: Sendable {
    func read() async throws -> CodexUsageSnapshot
}

struct NativeCodexUsageClient: CodexUsageClient {
    func read() async throws -> CodexUsageSnapshot {
        let files = FileManager.default
        let candidates = [files.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
                          "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let executable = candidates.first(where: { files.isExecutableFile(atPath: $0) }) else { throw CocoaError(.fileNoSuchFile) }
        let directory = files.temporaryDirectory.appendingPathComponent("nu-" + UUID().uuidString.prefix(8))
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let path = directory.appendingPathComponent("s")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "unix://" + path.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = files.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path + ":/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        // This reader only initializes and reads account limits; it never opens or joins a thread.
        for _ in 0..<100 {
            if files.fileExists(atPath: path.path) { break }
            guard process.isRunning else { throw CodexSocket.Failure.closed }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        guard files.fileExists(atPath: path.path) else { throw CodexSocket.Failure.timedOut }
        let socket = CodexSocket()
        do {
            try await socket.connect(path: path)
            _ = try await socket.call("initialize", params: Data(#"{"clientInfo":{"name":"notchent-usage","version":"0.1.0"}}"#.utf8))
            try await socket.notify("initialized")
            let data = try await socket.call("account/rateLimits/read", params: Data("{}".utf8))
            let usage = try CodexUsageSnapshot.decode(data)
            await socket.close()
            return usage
        } catch {
            await socket.close()
            throw error
        }
    }
}

@MainActor final class CodexUsageStore: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var refreshing = false
    private let client: any CodexUsageClient
    private var task: Task<Void, Never>?

    init(client: any CodexUsageClient = NativeCodexUsageClient()) { self.client = client }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do { snapshot = try await client.read() }
        catch { snapshot = nil }
    }
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}
