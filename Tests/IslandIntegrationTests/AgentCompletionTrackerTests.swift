import Foundation
import Testing
import IslandCore
@testable import IslandMac

struct AgentCompletionTrackerTests {
    private func agent(_ time: Double) -> DiscoveredAgent {
        let session = SessionID(ownerInstanceID: "codex-observed", pid: 42, processStartTime: 1, terminalSessionKey: "thread")
        return DiscoveredAgent(pid: 42, birth: 1, kind: .codex, host: .codexDesktop, sessionID: session,
                               ownedTerminal: nil, reason: "sessionReadOnly", completedAt: Date(timeIntervalSince1970: time))
    }
    @Test func oldCompletionsAndRepeatedPollingNeverNotify() {
        var tracker = AgentCompletionTracker(startedAt: Date(timeIntervalSince1970: 100))
        #expect(tracker.update([agent(99)]).isEmpty)
        #expect(tracker.update([agent(101)]).count == 1)
        #expect(tracker.update([agent(101)]).isEmpty)
        #expect(tracker.update([]).isEmpty)
        #expect(tracker.update([agent(101)]).isEmpty)
        #expect(tracker.update([agent(102)]).count == 1)
        #expect(tracker.update([agent(101)]).isEmpty)
    }
}
