import Foundation
import Testing
@testable import IslandCore

struct ClaudeUsageRecordTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(_ rateLimits: String, extra: String = "") -> Data {
        Data(#"{"model":{"display_name":"Opus"},"cwd":"/secret/project","transcript_path":"/x.jsonl"\#(extra),"rate_limits":\#(rateLimits)}"#.utf8)
    }

    @Test func extractsOnlyTheDocumentedWindows() throws {
        let data = input(#"{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41.2,"resets_at":1800400000}}"#)
        let record = try #require(ClaudeUsageRecord.extract(statusLineInput: data, now: now))
        #expect(record.fiveHour == .init(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)))
        #expect(record.sevenDay?.usedPercentage == 41.2)
        #expect(record.observedAt == now)
    }

    @Test func missingOrMalformedLimitsAreIgnored() {
        let cases = [
            Data(#"{"model":{"display_name":"Opus"}}"#.utf8),
            input("{}"),
            input(#"{"five_hour":{"used_percentage":true,"resets_at":1800003600}}"#),
            input(#"{"five_hour":{"used_percentage":-1,"resets_at":1800003600}}"#),
            input(#"{"five_hour":{"used_percentage":5}}"#),
            Data("not json".utf8),
        ]
        for data in cases { #expect(ClaudeUsageRecord.extract(statusLineInput: data, now: now) == nil) }
    }

    @Test func eachWindowCanBeAbsentIndependently() throws {
        let record = try #require(ClaudeUsageRecord.extract(statusLineInput: input(#"{"seven_day":{"used_percentage":90,"resets_at":1800400000}}"#), now: now))
        #expect(record.fiveHour == nil)
        #expect(record.sevenDay != nil)
    }

    @Test func currentDropsWindowsThatAlreadyReset() {
        let record = ClaudeUsageRecord(fiveHour: .init(usedPercentage: 80, resetsAt: now.addingTimeInterval(-1)),
                                       sevenDay: .init(usedPercentage: 30, resetsAt: now.addingTimeInterval(60)), observedAt: now)
        #expect(record.current(at: now)?.fiveHour == nil)
        #expect(record.current(at: now)?.sevenDay?.usedPercentage == 30)
        #expect(record.current(at: now.addingTimeInterval(61)) == nil)
    }

    @Test func relayReplacesThePreviousRecordWithAnOwnerOnlyFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeRelay-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let relay = ClaudeUsageRelay(directory: directory)
        #expect(relay.read() == nil)
        let first = ClaudeUsageRecord(fiveHour: .init(usedPercentage: 10, resetsAt: now), sevenDay: nil, observedAt: now)
        let second = ClaudeUsageRecord(fiveHour: nil, sevenDay: .init(usedPercentage: 55, resetsAt: now), observedAt: now)
        try relay.write(first)
        try relay.write(second)
        #expect(relay.read() == second)
        let attributes = try FileManager.default.attributesOfItem(atPath: relay.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let stored = try String(contentsOf: relay.fileURL, encoding: .utf8)
        #expect(!stored.contains("secret"))
    }

    @Test func statusLineShowsModelAndUsedPercentages() {
        let record = ClaudeUsageRecord(fiveHour: .init(usedPercentage: 23.5, resetsAt: now),
                                       sevenDay: .init(usedPercentage: 41.2, resetsAt: now), observedAt: now)
        #expect(ClaudeStatusLine.text(statusLineInput: input("{}"), record: record) == "Opus · 5h 24% · 7d 41%")
        #expect(ClaudeStatusLine.text(statusLineInput: Data("{}".utf8), record: nil) == "Claude")
    }
}
