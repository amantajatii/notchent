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
}
