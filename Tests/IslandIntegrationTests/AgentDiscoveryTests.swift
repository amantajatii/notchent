import Foundation
import Testing
import IslandCore
@testable import IslandMac

struct AgentDiscoveryTests {
    private func record(_ pid: Int32, parent: Int32, birth: UInt64 = 1, tty: UInt32 = 42, path: String) -> HostSessionDiscovery.ProcessRecord {
        .init(pid: pid, parent: parent, birth: birth, tty: tty, executable: path)
    }
    @Test func ownedDescendantUsesAgentPIDAndShellPane() {
        let shell = SessionID(ownerInstanceID: "app", pid: 10, processStartTime: 1, terminalSessionKey: "owned-pane")
        let records = [record(10, parent: 1, path: "/bin/zsh"), record(20, parent: 10, birth: 2, path: "/bin/codex")]
        let found = HostSessionDiscovery.discover(records: records, owned: [shell])
        #expect(found.count == 1); #expect(found.first?.sessionID?.pid == 20)
        #expect(found.first?.sessionID?.terminalSessionKey == "owned-pane")
        #expect(found.first?.ownedTerminal == shell)
        let reused = SessionID(ownerInstanceID: "app", pid: 10, processStartTime: 9, terminalSessionKey: "owned-pane")
        #expect(HostSessionDiscovery.discover(records: records, owned: [reused]).first?.sessionID == nil)
    }
    @Test func externalHostTTYIsCandidateNeverFabricatedPane() {
        for (path, host) in [("/Applications/Visual Studio Code.app/Contents/MacOS/Electron", HostKind.vscode), ("/Applications/Orca.app/Contents/MacOS/Orca", .orca), ("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", .terminal), ("/Applications/iTerm.app/Contents/MacOS/iTerm2", .iterm2)] {
            let records = [record(1, parent: 0, path: path), record(10, parent: 1, path: "/bin/zsh"), record(20, parent: 10, path: "/bin/claude")]
            let candidate = HostSessionDiscovery.discover(records: records, owned: []).first
            #expect(candidate?.host == host); #expect(candidate?.sessionID == nil)
            #expect(candidate?.reason == "externalPaneUnknown")
        }
    }
    @Test func knownExecutablesAndAmbiguousScripts() {
        #expect(HostSessionDiscovery.kind(for: "/bin/agy") == .antigravity)
        #expect(HostSessionDiscovery.kind(for: "/bin/omp") == .ohMyPi)
        #expect(HostSessionDiscovery.kind(for: "/bin/node") == nil)
    }
    @Test func liveMetadataScanDoesNotClaimActivity() {
        let records = HostSessionDiscovery.snapshot()
        #expect(!records.isEmpty)
        let found = HostSessionDiscovery.discover(records: records, owned: [])
        print("Public metadata scan: \(records.count) same-user records, \(found.count) known executable candidates, \(found.filter { $0.host != nil }.count) target-host candidates; stable external panes unavailable")
        #expect(found.allSatisfy { $0.sessionID == nil })
    }
    @Test func allNativeAdaptersFailClosed() async {
        let id = SessionID(ownerInstanceID: "test", pid: 1, processStartTime: 1, terminalSessionKey: "pane")
        let prompt = AgentPrompt(id: PromptID("p"), sessionID: id, revision: 1, text: "?", choices: [], acceptsText: true)
        for kind in AgentKind.allCases {
            let adapter = NativeAgentAdapter(kind: kind)
            await #expect(throws: AgentRoutingError.unavailable) { try await adapter.validate(sessionID: id) }
            await #expect(throws: AgentRoutingError.unavailable) { try await adapter.respond(prompt: prompt, response: .text("yes")) }
            await #expect(throws: AgentRoutingError.unavailable) { try await adapter.openOrigin(sessionID: id) }
        }
    }
}
