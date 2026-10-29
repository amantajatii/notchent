import Foundation
import Darwin
import Testing
import IslandCore
@testable import IslandMac

struct AgentDiscoveryTests {
    private func record(_ pid: Int32, parent: Int32, birth: UInt64 = 1, tty: UInt32 = 42, path: String) -> HostSessionDiscovery.ProcessRecord {
        .init(pid: pid, parent: parent, birth: birth, tty: tty, executable: path)
    }
    @Test func sharedDaemonWithoutTTYIsDiscoverableButUnrelatedProcessesAreRejected() {
        let home = URL(fileURLWithPath: "/Users/test/.codex")
        var daemon = record(50, parent: 1, tty: UInt32.max,
                            path: "/Users/test/.codex/packages/app-server-daemon/releases/1/bin/codex")
        #expect(CodexAdapter.sharedDaemon(in: [daemon], home: home)?.pid == 50)
        daemon.uid = getuid() &+ 1
        #expect(CodexAdapter.sharedDaemon(in: [daemon], home: home) == nil)
        let unrelated = record(51, parent: 1, path: "/Applications/Codex.app/codex")
        let sibling = record(52, parent: 1, path: "/Users/test/.codex/packages/app-server-daemon-other/codex")
        #expect(CodexAdapter.sharedDaemon(in: [unrelated, sibling], home: home) == nil)
    }
    @Test func daemonThreadsHaveDistinctCardIdentities() {
        let first = SessionID(ownerInstanceID: "daemon", pid: 50, processStartTime: 1, terminalSessionKey: "one")
        let second = SessionID(ownerInstanceID: "daemon", pid: 50, processStartTime: 1, terminalSessionKey: "two")
        let a = DiscoveredAgent(pid: 50, birth: 1, kind: .codex, host: nil, sessionID: first, ownedTerminal: nil, reason: "codexMonitoring")
        let b = DiscoveredAgent(pid: 50, birth: 1, kind: .codex, host: nil, sessionID: second, ownedTerminal: nil, reason: "codexMonitoring")
        #expect(a.id != b.id)
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
    @Test func desktopCodexWithoutTTYHasAHostButNoFabricatedSession() {
        let app = record(10, parent: 1, tty: UInt32.max, path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")
        let agent = record(20, parent: 10, tty: UInt32.max, path: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        let candidate = HostSessionDiscovery.discover(records: [app, agent], owned: []).first
        #expect(candidate?.host == .codexDesktop)
        #expect(candidate?.reason == "externalHostOnly")
        #expect(candidate?.sessionID == nil)
    }
    @Test func knownExecutablesAndAmbiguousScripts() {
        #expect(HostSessionDiscovery.kind(for: "/bin/agy") == .antigravity)
        #expect(HostSessionDiscovery.kind(for: "/bin/omp") == .ohMyPi)
        #expect(HostSessionDiscovery.kind(for: "/bin/node") == nil)
    }
    @Test func terminalLoginAncestorDoesNotHideUserAgent() {
        let terminal = record(1, parent: 0, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        var login = record(2, parent: 1, path: "/usr/bin/login")
        login.uid = 0
        let shell = record(3, parent: 2, path: "/bin/zsh")
        let agent = record(4, parent: 3, path: "/bin/codex")
        let records = HostSessionDiscovery.completingAncestors([terminal, shell, agent]) { $0 == login.pid ? login : nil }
        let found = HostSessionDiscovery.discover(records: records, owned: [])
        #expect(found.count == 1)
        #expect(found.first?.host == .terminal)
        #expect(found.first?.reason == "externalPaneUnknown")
        #expect(found.first?.sessionID == nil)
    }
    @Test func rootAndOtherUserAgentsAreNeverCandidates() {
        var root = record(1, parent: 0, path: "/bin/codex"); root.uid = 0
        var other = record(2, parent: 0, path: "/bin/claude"); other.uid = getuid() &+ 1
        #expect(HostSessionDiscovery.discover(records: [root, other], owned: []).isEmpty)
        let own = record(3, parent: 2, path: "/bin/zsh")
        let completed = HostSessionDiscovery.completingAncestors([own]) { $0 == other.pid ? other : nil }
        #expect(completed.count == 1)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_CODEX_LIVE"] == "1", "Requires existing shared Codex daemon"))
    func liveDaemonWithoutTerminalConnectsAndPublishesVerifiedCards() async throws {
        let adapter = CodexAdapter()
        await adapter.refresh(records: HostSessionDiscovery.snapshot())
        let connected = await adapter.isConnected
        let cards = await adapter.monitoredAgents
        await adapter.disconnect()
        #expect(connected)
        #expect(Set(cards.map(\.id)).count == cards.count)
        print("Live shared daemon: connected=\(connected), verified active session cards=\(cards.count); no replies sent")
    }
    @Test func liveMetadataScanDoesNotClaimActivity() {
        let records = HostSessionDiscovery.snapshot()
        #expect(!records.isEmpty)
        let found = HostSessionDiscovery.discover(records: records, owned: [])
        print("Public metadata scan: \(records.count) process/ancestor records, \(found.count) known executable candidates, \(found.filter { $0.host != nil }.count) target-host candidates; stable external panes unavailable")
        #expect(found.allSatisfy { $0.sessionID == nil })
    }
    @Test func allNativeAdaptersFailClosed() async {
        let id = SessionID(ownerInstanceID: "test", pid: 1, processStartTime: 1, terminalSessionKey: "pane")
        let prompt = AgentPrompt(id: PromptID(sessionID: id, localRequestID: "p"), revision: 1, text: "?", choices: [], acceptsText: true)
        for kind in AgentKind.allCases {
            let adapter = NativeAgentAdapter(kind: kind)
            await #expect(throws: AgentRoutingError.unavailable) { try await adapter.validate(sessionID: id) }
            await #expect(throws: AgentRoutingError.unavailable) { try await adapter.respond(prompt: prompt, response: .text("yes")) }
            await #expect(throws: AgentRoutingError.unavailable) { try await adapter.openOrigin(sessionID: id) }
        }
    }
}
