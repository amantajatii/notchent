import Foundation

public enum IslandLanguage: String, Codable, CaseIterable, Sendable { case en, id }
public enum FullScreenPromptPolicy: String, Codable, CaseIterable, Sendable { case indicator, automatic }
public enum FileStorageMode: String, Codable, CaseIterable, Sendable { case copy, reference }
/// When the black pill stays on screen while nothing is open.
public enum PillVisibility: String, Codable, CaseIterable, Sendable {
    /// Always on a screen with a camera notch, hover-only elsewhere.
    case automatic
    case always
    case hover
    public func showsAtRest(screenHasNotch: Bool) -> Bool {
        switch self {
        case .automatic: screenHasNotch
        case .always: true
        case .hover: false
        }
    }
}
public struct IslandSettings: Codable, Equatable, Sendable {
    public var language: IslandLanguage = .en
    public var openDelayMilliseconds = 450
    public var closeDelayMilliseconds = 1000
    public var fullScreenPrompts: FullScreenPromptPolicy = .indicator
    public var fileStorage: FileStorageMode = .copy
    public var pillVisibility: PillVisibility = .automatic
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case language, openDelayMilliseconds, closeDelayMilliseconds, fullScreenPrompts, fileStorage, pillVisibility
    }
    /// Missing keys keep their defaults, so settings saved by older builds still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IslandSettings()
        language = try c.decodeIfPresent(IslandLanguage.self, forKey: .language) ?? d.language
        openDelayMilliseconds = try c.decodeIfPresent(Int.self, forKey: .openDelayMilliseconds) ?? d.openDelayMilliseconds
        closeDelayMilliseconds = try c.decodeIfPresent(Int.self, forKey: .closeDelayMilliseconds) ?? d.closeDelayMilliseconds
        fullScreenPrompts = try c.decodeIfPresent(FullScreenPromptPolicy.self, forKey: .fullScreenPrompts) ?? d.fullScreenPrompts
        fileStorage = try c.decodeIfPresent(FileStorageMode.self, forKey: .fileStorage) ?? d.fileStorage
        pillVisibility = try c.decodeIfPresent(PillVisibility.self, forKey: .pillVisibility) ?? d.pillVisibility
    }
    public var isValid: Bool { (0...5000).contains(openDelayMilliseconds) && (0...10000).contains(closeDelayMilliseconds) }
}
public struct SettingsStore: Sendable {
    public let url: URL
    public init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IslandMac/settings.json")) { self.url = url }
    public func load() throws -> IslandSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return IslandSettings() }
        let data = try Data(contentsOf: url)
        guard let settings = try? JSONDecoder().decode(IslandSettings.self, from: data), settings.isValid else { return IslandSettings() }
        return settings
    }
    public func save(_ settings: IslandSettings) throws {
        guard settings.isValid else { throw CocoaError(.coderInvalidValue) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
    }
}
