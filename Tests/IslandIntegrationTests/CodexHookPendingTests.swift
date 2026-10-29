import Foundation
import Darwin
import Testing
import IslandCore
@testable import IslandMac

struct CodexHookPendingTests {
    private let helper = "/private/IslandHook"
    private func records() -> [HostSessionDiscovery.ProcessRecord] {
        [.init(pid: 71, parent: 1, birth: 1, tty: UInt32.max, executable: "/bin/codex"),
         .init(pid: 72, parent: 71, birth: 2, tty: UInt32.max, executable: helper)]
    }
    private func envelope(event: String = "PermissionRequest", name: String = "Bash", input: [String: Any] = ["command": "pwd"]) throws -> CodexHookEnvelope {
        let data = try JSONSerialization.data(withJSONObject: ["session_id": "01a17228-62b4-7de3-8486-b52b4bd9f8cf", "turn_id": "turn", "cwd": "/project", "hook_event_name": event, "tool_name": name, "tool_input": input])
        return CodexHookEnvelope(pid: 72, birth: 2, input: data)
    }
    @Test func permissionIsBoundToExactHelperBirthAndCodexAncestry() throws {
        let event = try envelope()
        let pending = try #require(CodexHookPending.decode(event, records: records(), helperPath: helper))
        #expect(pending.prompt.choices.map(\.id) == ["hookAllow", "hookDeny", "hookContinue"])
        #expect(pending.prompt.text.contains("pwd"))
        #expect(pending.prompt.sessionID.processStartTime == 2)
        #expect(CodexHookPending.decode(event, records: records(), helperPath: "/wrong/helper") == nil)
        #expect(CodexHookPending.decode(event, records: Array(records().suffix(1)), helperPath: helper) == nil)
        #expect(CodexHookPending.decode(event, records: records(), helperPath: helper, now: event.createdAt.addingTimeInterval(121)) == nil)
        var other = records(); other[1].uid = getuid() &+ 1
        #expect(CodexHookPending.decode(event, records: other, helperPath: helper) == nil)
    }
    @Test func preferenceNoticeCannotApproveOrInventAToolAnswer() throws {
        let question: [String: Any] = ["question": "Which layout?", "options": [["label": "Compact"], ["label": "Wide"]]]
        let event = try envelope(event: "PreToolUse", name: "functions.request_user_input_async", input: ["questions": [question]])
        let pending = try #require(CodexHookPending.decode(event, records: records(), helperPath: helper))
        #expect(pending.prompt.text.contains("Compact"))
        #expect(pending.prompt.choices.map(\.id) == ["hookContinue"])
        #expect(!pending.prompt.acceptsText)
        var secret = question; secret["isSecret"] = true
        let hidden = try envelope(event: "PreToolUse", name: "request_user_input", input: ["questions": [secret]])
        #expect(CodexHookPending.decode(hidden, records: records(), helperPath: helper) == nil)
    }
}
