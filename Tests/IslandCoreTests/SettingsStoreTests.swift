import Foundation
import Testing
@testable import IslandCore
struct SettingsStoreTests {
    @Test func defaultsRoundTripAndCorruption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let store = SettingsStore(url: url)
        #expect(try store.load() == IslandSettings())
        #expect(try store.load().language == .en)
        var settings = IslandSettings(); settings.language = .id
        try store.save(settings)
        #expect(try store.load() == settings)
        try Data("invalid".utf8).write(to: url)
        #expect(try store.load() == IslandSettings())
    }
    @Test func olderSettingsFileKeepsValuesAndGainsNewDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = #"{"language":"id","openDelayMilliseconds":300,"closeDelayMilliseconds":900,"fullScreenPrompts":"automatic","fileStorage":"reference"}"#
        try Data(legacy.utf8).write(to: url)
        let loaded = try SettingsStore(url: url).load()
        #expect(loaded.language == .id && loaded.openDelayMilliseconds == 300 && loaded.fileStorage == .reference)
        #expect(loaded.pillVisibility == .automatic)
    }
    @Test func pillVisibilityFollowsTheScreen() {
        #expect(PillVisibility.automatic.showsAtRest(screenHasNotch: true))
        #expect(!PillVisibility.automatic.showsAtRest(screenHasNotch: false))
        #expect(PillVisibility.always.showsAtRest(screenHasNotch: false))
        #expect(!PillVisibility.hover.showsAtRest(screenHasNotch: true))
    }
}
