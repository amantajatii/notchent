import CryptoKit
import Foundation

protocol UpdateInstalling: Sendable {
    /// Checks that the running app can replace itself, without touching anything.
    func canInstall(at target: URL) -> Bool
    /// Downloads, verifies, and stages the release next to `target`, then starts a helper that
    /// swaps it in after this process exits. The caller must then quit the app.
    func stage(_ release: ReleaseInfo, replacing target: URL) async throws
}

/// Installs a GitHub release over the running app bundle.
///
/// Safety: only this repository's HTTPS release assets are fetched, the archive must match its
/// published SHA-256, and the extracted bundle must have the same identifier, the expected version,
/// and a valid code signature before anything is replaced. The old bundle is restored on failure.
struct NativeUpdateInstaller: UpdateInstalling {
    static let maximumArchiveBytes: Int64 = 200_000_000
    /// How long the helper waits for the app to quit (e.g. while terminal sessions ask to close).
    static let quitTimeoutSeconds = 600

    let bundleIdentifier: String
    let session: URLSession

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.nativeisland.app", session: URLSession = .shared) {
        self.bundleIdentifier = bundleIdentifier
        self.session = session
    }

    func canInstall(at target: URL) -> Bool {
        target.pathExtension == "app" && !target.path.contains("/.build/")
            && FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    func stage(_ release: ReleaseInfo, replacing target: URL) async throws {
        guard canInstall(at: target) else { throw UpdateError.notInstalled }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("notchent-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let archive = try await download(release.archiveURL, to: work.appendingPathComponent("Notchent.zip"))
            let checksum = try await String(contentsOf: download(release.checksumURL, to: work.appendingPathComponent("Notchent.zip.sha256")), encoding: .utf8)
            guard try Self.sha256(of: archive) == Self.expectedDigest(checksum) else { throw UpdateError.checksumMismatch }
            let extracted = work.appendingPathComponent("extracted")
            try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path], failure: .invalidBundle)
            let app = extracted.appendingPathComponent("Notchent.app")
            try validate(app, version: release.version)
            // Stage beside the target so the final swap is a same-volume rename.
            let staged = target.deletingLastPathComponent().appendingPathComponent(".Notchent-update-\(UUID().uuidString).app")
            try Self.run("/usr/bin/ditto", [app.path, staged.path], failure: .installFailed)
            try launchSwapHelper(target: target, staged: staged, work: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error as? UpdateError ?? .installFailed
        }
    }

    private func download(_ url: URL, to destination: URL) async throws -> URL {
        let (temporary, response): (URL, URLResponse)
        do { (temporary, response) = try await session.download(from: url) } catch { throw UpdateError.network }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= Self.maximumArchiveBytes else { throw UpdateError.network }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    func validate(_ app: URL, version: AppVersion) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == version else { throw UpdateError.invalidBundle }
        try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], failure: .invalidBundle)
    }

    private func launchSwapHelper(target: URL, staged: URL, work: URL) throws {
        let script = work.appendingPathComponent("swap.sh")
        try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(getpid()), target.path, staged.path, work.path, "open", String(Self.quitTimeoutSeconds)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UpdateError.installFailed }
    }

    static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the digest from `shasum -a 256` output ("<hex>  Notchent-X.Y.Z.zip").
    static func expectedDigest(_ text: String) throws -> String {
        let digest = text.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { throw UpdateError.checksumMismatch }
        return digest
    }

    private static func run(_ executable: String, _ arguments: [String], failure: UpdateError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw failure }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure }
    }

    /// Waits for the app to exit, swaps the bundles (restoring the old one on failure), and relaunches.
    /// Arguments: pid target staged workdir open|no-open timeoutSeconds.
    static let swapScript = #"""
    #!/bin/sh
    pid=$1 target=$2 staged=$3 work=$4 reopen=$5 timeout=$6
    waited=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$((timeout * 2))" ]; then rm -rf "$staged" "$work"; exit 1; fi
      waited=$((waited + 1)); sleep 0.5
    done
    backup="$target.notchent-old"
    rm -rf "$backup"
    if [ -e "$target" ] && ! mv "$target" "$backup"; then rm -rf "$staged" "$work"; exit 1; fi
    if mv "$staged" "$target"; then rm -rf "$backup"; else rm -rf "$staged"; [ -e "$backup" ] && mv "$backup" "$target"; fi
    rm -rf "$work"
    [ "$reopen" = open ] && /usr/bin/open "$target"
    exit 0
    """#
}
