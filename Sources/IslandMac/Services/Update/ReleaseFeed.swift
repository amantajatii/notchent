import Foundation

/// A three-part semantic version such as 0.3.0 (a leading "v" is accepted).
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) ? Int(part) : nil }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// The version of the running app bundle.
    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }
}

/// A published release whose download assets passed basic validation.
struct ReleaseInfo: Equatable, Sendable {
    let version: AppVersion
    let archiveURL: URL
    let checksumURL: URL
    let pageURL: URL?
}

enum UpdateError: Error, Equatable, Sendable {
    case network
    case noRelease
    case missingAsset
    case checksumMismatch
    case invalidBundle
    case notInstalled
    case installFailed

    /// Localization key for the message shown in Settings.
    var messageKey: String {
        switch self {
        case .network: "updateErrorNetwork"
        case .noRelease: "updateErrorNoRelease"
        case .missingAsset: "updateErrorAsset"
        case .checksumMismatch: "updateErrorChecksum"
        case .invalidBundle: "updateErrorBundle"
        case .notInstalled: "updateErrorNotInstalled"
        case .installFailed: "updateErrorInstall"
        }
    }
}

protocol ReleaseFeed: Sendable {
    func latest() async throws -> ReleaseInfo
}

/// Reads the latest release of the public GitHub repository. Assets follow
/// `Notchent-X.Y.Z.zip` and `Notchent-X.Y.Z.zip.sha256` (see scripts/package-release.sh).
struct GitHubReleaseFeed: ReleaseFeed {
    static let repository = "amantajatii/notchent"
    static let maximumResponseBytes = 1_000_000

    let repository: String
    let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(repository: String = Self.repository,
         load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.repository = repository
        self.load = load
    }

    func latest() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { throw UpdateError.network }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Notchent-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await load(request) } catch { throw UpdateError.network }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError.noRelease }
        guard status == 200, data.count <= Self.maximumResponseBytes else { throw UpdateError.network }
        return try Self.parse(data, repository: repository)
    }

    static func parse(_ data: Data, repository: String) throws -> ReleaseInfo {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Release: Decodable { let tag_name: String; let html_url: String?; let draft: Bool?; let prerelease: Bool?; let assets: [Asset] }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              let version = AppVersion(release.tag_name) else { throw UpdateError.noRelease }
        let archiveName = "Notchent-\(version).zip"
        func assetURL(_ name: String) -> URL? {
            guard let asset = release.assets.first(where: { $0.name == name }),
                  let url = URL(string: asset.browser_download_url), isTrustedDownload(url, repository: repository) else { return nil }
            return url
        }
        guard let archive = assetURL(archiveName), let checksum = assetURL(archiveName + ".sha256") else { throw UpdateError.missingAsset }
        return ReleaseInfo(version: version, archiveURL: archive, checksumURL: checksum, pageURL: release.html_url.flatMap(URL.init(string:)))
    }

    /// Only this repository's release downloads over HTTPS are accepted.
    static func isTrustedDownload(_ url: URL, repository: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(repository)/releases/download/")
    }
}
