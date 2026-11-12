import Foundation
import Testing
@testable import IslandMac

private let repo = "amantajatii/notchent"

private func releaseJSON(tag: String = "v0.3.0", host: String = "github.com", prerelease: Bool = false) -> Data {
    let base = "https://\(host)/\(repo)/releases/download/\(tag)/Notchent-0.3.0.zip"
    return Data("""
    {"tag_name":"\(tag)","html_url":"https://github.com/\(repo)/releases/tag/\(tag)","draft":false,"prerelease":\(prerelease),
     "assets":[{"name":"Notchent-0.3.0.zip","browser_download_url":"\(base)"},
               {"name":"Notchent-0.3.0.zip.sha256","browser_download_url":"\(base).sha256"}]}
    """.utf8)
}

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateTests-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct AppVersionTests {
    @Test func parsesAndOrdersSemanticVersions() throws {
        #expect(AppVersion("v0.3.0")?.description == "0.3.0")
        #expect(try #require(AppVersion("0.10.0")) > #require(AppVersion("0.9.9")))
        #expect(try #require(AppVersion("1.0.0")) > #require(AppVersion("0.99.99")))
        for bad in ["", "1.2", "1.2.3.4", "v1.x.0", "1.-2.0", "１.0.0"] { #expect(AppVersion(bad) == nil) }
    }
}

struct GitHubReleaseFeedTests {
    @Test func parsesLatestReleaseAssets() throws {
        let release = try GitHubReleaseFeed.parse(releaseJSON(), repository: repo)
        #expect(release.version.description == "0.3.0")
        #expect(release.archiveURL.lastPathComponent == "Notchent-0.3.0.zip")
        #expect(release.checksumURL.lastPathComponent == "Notchent-0.3.0.zip.sha256")
    }

    @Test func rejectsForeignHostsPrereleasesAndBadTags() {
        #expect(throws: UpdateError.missingAsset) { try GitHubReleaseFeed.parse(releaseJSON(host: "evil.example"), repository: repo) }
        #expect(throws: UpdateError.missingAsset) { try GitHubReleaseFeed.parse(releaseJSON(tag: "v0.4.0"), repository: repo) }
        #expect(throws: UpdateError.noRelease) { try GitHubReleaseFeed.parse(releaseJSON(prerelease: true), repository: repo) }
        #expect(throws: UpdateError.noRelease) { try GitHubReleaseFeed.parse(releaseJSON(tag: "latest"), repository: repo) }
        #expect(!GitHubReleaseFeed.isTrustedDownload(URL(string: "http://github.com/\(repo)/releases/download/x")!, repository: repo))
        #expect(!GitHubReleaseFeed.isTrustedDownload(URL(string: "https://github.com/other/notchent/releases/download/x")!, repository: repo))
    }

    @Test func mapsHTTPStatusToErrors() async throws {
        func feed(_ status: Int, _ data: Data = Data()) -> GitHubReleaseFeed {
            GitHubReleaseFeed(repository: repo) { request in
                (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        }
        #expect(try await feed(200, releaseJSON()).latest().version.description == "0.3.0")
        await #expect(throws: UpdateError.noRelease) { try await feed(404).latest() }
        await #expect(throws: UpdateError.network) { try await feed(500).latest() }
        let offline = GitHubReleaseFeed(repository: repo) { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: UpdateError.network) { try await offline.latest() }
    }
}

struct UpdateInstallerTests {
    @Test func checksumParsingAndHashing() throws {
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(try NativeUpdateInstaller.expectedDigest("\(digest.uppercased())  Notchent-0.3.0.zip\n") == digest)
        #expect(throws: UpdateError.checksumMismatch) { try NativeUpdateInstaller.expectedDigest("nope") }
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: file)
        #expect(try NativeUpdateInstaller.sha256(of: file) == digest)
    }

    private func makeBundle(in directory: URL, identifier: String, version: String, sign: Bool) throws -> URL {
        let app = directory.appendingPathComponent("Notchent.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("IslandMac"))
        let info: NSDictionary = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                  "CFBundleExecutable": "IslandMac", "CFBundlePackageType": "APPL"]
        info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        if sign {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--force", "--sign", "-", app.path]
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
        }
        return app
    }

    @Test func validatesIdentifierVersionAndSignature() throws {
        let installer = NativeUpdateInstaller(bundleIdentifier: "dev.nativeisland.app")
        let version = try #require(AppVersion("0.3.0"))
        let good = try scratch(), wrongID = try scratch(), unsigned = try scratch()
        defer { for url in [good, wrongID, unsigned] { try? FileManager.default.removeItem(at: url) } }
        let goodApp = try makeBundle(in: good, identifier: "dev.nativeisland.app", version: "0.3.0", sign: true)
        try installer.validate(goodApp, version: version)
        #expect(throws: UpdateError.invalidBundle) {
            try installer.validate(makeBundle(in: wrongID, identifier: "com.example.other", version: "0.3.0", sign: true), version: version)
        }
        #expect(throws: UpdateError.invalidBundle) {
            try installer.validate(goodApp, version: AppVersion("0.4.0")!)
        }
        #expect(throws: UpdateError.invalidBundle) {
            try installer.validate(makeBundle(in: unsigned, identifier: "dev.nativeisland.app", version: "0.3.0", sign: false), version: version)
        }
    }

    @Test func onlyInstalledBundlesCanSelfUpdate() throws {
        let installer = NativeUpdateInstaller()
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(installer.canInstall(at: directory.appendingPathComponent("Notchent.app")))
        #expect(!installer.canInstall(at: URL(fileURLWithPath: "/tmp/repo/.build/apps/Notchent.app")))
        #expect(!installer.canInstall(at: directory.appendingPathComponent("Notchent")))
    }

    private func runSwap(target: URL, staged: URL, work: URL) throws {
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run(); finished.waitUntilExit()
        let script = work.appendingPathComponent("swap.sh")
        try NativeUpdateInstaller.swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(finished.processIdentifier), target.path, staged.path, work.path, "no-open", "5"]
        try process.run(); process.waitUntilExit()
    }

    @Test func swapReplacesTheBundleAndCleansUp() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Notchent.app"), staged = root.appendingPathComponent(".staged.app")
        let work = root.appendingPathComponent("work")
        for (url, marker) in [(target, "old"), (staged, "new")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
        }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try runSwap(target: target, staged: staged, work: work)
        #expect(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) == "new")
        for leftover in [staged, work, URL(fileURLWithPath: target.path + ".notchent-old")] {
            #expect(!FileManager.default.fileExists(atPath: leftover.path))
        }
    }

    @Test func failedSwapKeepsTheOldBundle() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Notchent.app"), work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try runSwap(target: target, staged: root.appendingPathComponent("missing.app"), work: work)
        #expect(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) == "old")
    }
}

private struct FakeFeed: ReleaseFeed {
    let result: Result<String, UpdateError>
    func latest() async throws -> ReleaseInfo {
        let version = try #require(AppVersion(try result.get()))
        let url = URL(string: "https://github.com/\(repo)/releases/download/v\(version)/Notchent-\(version).zip")!
        return ReleaseInfo(version: version, archiveURL: url, checksumURL: url.appendingPathExtension("sha256"), pageURL: nil)
    }
}

private final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
    let installable: Bool
    private(set) var staged: [AppVersion] = []
    init(installable: Bool) { self.installable = installable }
    func canInstall(at target: URL) -> Bool { installable }
    func stage(_ release: ReleaseInfo, replacing target: URL) async throws { staged.append(release.version) }
}

@MainActor struct UpdateStoreTests {
    private func store(feed: Result<String, UpdateError>, current: String = "0.2.0", installable: Bool = true,
                       quits: @escaping @MainActor () -> Void = {}) -> (UpdateStore, FakeInstaller) {
        let installer = FakeInstaller(installable: installable)
        return (UpdateStore(feed: FakeFeed(result: feed), installer: installer, currentVersion: AppVersion(current),
                            bundleURL: URL(fileURLWithPath: "/Applications/Notchent.app"), quit: quits), installer)
    }

    @Test func reportsUpToDateWhenNotNewer() async {
        let (updates, _) = store(feed: .success("0.2.0"))
        await updates.check()
        #expect(updates.phase == .upToDate)
    }

    @Test func installsAvailableReleaseThenQuits() async {
        var quitCount = 0
        let (updates, installer) = store(feed: .success("0.3.0")) { quitCount += 1 }
        await updates.check()
        guard case .available(let release) = updates.phase else { Issue.record("expected available"); return }
        #expect(release.version.description == "0.3.0")
        await updates.install()
        #expect(installer.staged.map(\.description) == ["0.3.0"])
        #expect(quitCount == 1)
    }

    @Test func developmentBuildsCannotInstall() async {
        var quitCount = 0
        let (updates, installer) = store(feed: .success("0.3.0"), installable: false) { quitCount += 1 }
        await updates.check()
        await updates.install()
        #expect(updates.phase == .failed(.notInstalled))
        #expect(installer.staged.isEmpty && quitCount == 0)
    }

    @Test func surfacesFeedErrors() async {
        let (updates, _) = store(feed: .failure(.noRelease))
        await updates.check()
        #expect(updates.phase == .failed(.noRelease))
    }
}
