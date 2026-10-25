import Foundation

public enum IslandLanguage: String, Codable, CaseIterable, Sendable { case en, id }
public enum FullScreenPromptPolicy: String, Codable, CaseIterable, Sendable { case indicator, automatic }
public enum FileStorageMode: String, Codable, CaseIterable, Sendable { case copy, reference }
public struct IslandSettings: Codable, Equatable, Sendable {
    public var language: IslandLanguage = .en
    public var openDelayMilliseconds = 450
    public var closeDelayMilliseconds = 1000
    public var fullScreenPrompts: FullScreenPromptPolicy = .indicator
    public var fileStorage: FileStorageMode = .copy
    public init() {}
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
