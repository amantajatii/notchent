import Foundation
import Testing
@testable import IslandCore

struct CodexHookMailboxTests {
    @Test func privateMailboxRejectsSymlinksAndNeverOverwritesResponses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mailbox = CodexHookMailbox(root: root)
        try mailbox.prepare()
        let response = root.appendingPathComponent("response")
        try mailbox.write(Data("hookDeny".utf8), to: response)
        #expect(mailbox.read(response) == Data("hookDeny".utf8))
        #expect(throws: (any Error).self) { try mailbox.write(Data("hookAllow".utf8), to: response) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: response)
        #expect(mailbox.read(link) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: response.path)
        #expect(mailbox.read(response) == nil)
    }
    @Test func onlyExplicitPermissionChoicesCanReturnDecisions() throws {
        let allowed = try JSONSerialization.jsonObject(with: CodexHookMailbox.decision(event: "PermissionRequest", choice: "hookAllow")) as? [String: [String: Any]]
        #expect((allowed?["hookSpecificOutput"]?["decision"] as? [String: String])?["behavior"] == "allow")
        #expect(try CodexHookMailbox.decision(event: "PreToolUse", choice: "hookContinue") == Data("{}".utf8))
        #expect(throws: AgentRoutingError.invalidResponse) { try CodexHookMailbox.decision(event: "PreToolUse", choice: "hookAllow") }
        #expect(throws: AgentRoutingError.invalidResponse) { try CodexHookMailbox.decision(event: "PermissionRequest", choice: "allowAlways") }
    }
}
