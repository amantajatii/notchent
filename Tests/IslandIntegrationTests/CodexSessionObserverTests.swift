import Foundation
import Testing
@testable import IslandMac

struct CodexSessionObserverTests {
    private let id = "01a17228-62b4-7de3-8486-b52b4bd9f8cf"
    private func line(_ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
        data.append(10)
        return data
    }
    @Test func sessionMetadataAndLifecycleDoNotDependOnDaemonOrTTY() throws {
        let header = try line("session_meta", ["id": id, "cwd": "/projects/example"])
        let completed = try line("event_msg", ["type": "task_complete", "last_agent_message": "Finished the requested change."])
        let snapshot = try #require(CodexSessionObserver.parse(header: header, tail: completed))
        #expect(snapshot.id == id && snapshot.project == "/projects/example")
        #expect(snapshot.status == "sessionCompleted")
        #expect(snapshot.summary == "Finished the requested change.")
        let started = try line("event_msg", ["type": "task_started"])
        let working = try #require(CodexSessionObserver.parse(header: header, tail: completed + started))
        #expect(working.status == "sessionWorking" && working.summary == nil)
    }
    @Test func completedMessageSupportsScrollingBeyondPreview() throws {
        let header = try line("session_meta", ["id": id, "cwd": "/projects/example"])
        let message = String(repeating: "a", count: 900) + " end"
        let completed = try line("event_msg", ["type": "task_complete", "last_agent_message": message])
        #expect(CodexSessionObserver.parse(header: header, tail: completed)?.summary == message)
    }
    @Test func desktopHistoryShowsUserAndFinalMessagesOnly() throws {
        let user = try line("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Hello"]]])
        let final = try line("response_item", ["type": "message", "role": "assistant", "phase": "final_answer", "content": [["type": "output_text", "text": "Done"]]])
        let commentary = try line("response_item", ["type": "message", "role": "assistant", "phase": "commentary", "content": [["type": "output_text", "text": "Working"]]])
        let developer = try line("response_item", ["type": "message", "role": "developer", "content": [["type": "input_text", "text": "Hidden"]]])
        #expect(CodexSessionObserver.chatEntry(line: user, index: 0)?.text == "Hello")
        #expect(CodexSessionObserver.chatEntry(line: final, index: 1)?.text == "Done")
        #expect(CodexSessionObserver.chatEntry(line: commentary, index: 2) == nil)
        #expect(CodexSessionObserver.chatEntry(line: developer, index: 3) == nil)
        let context = try line("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": "<environment_context>private</environment_context>"], ["type": "input_text", "text": "Actual request"]]])
        #expect(CodexSessionObserver.chatEntry(line: context, index: 4)?.text == "Actual request")
    }
    @Test func imageOnlyUserMessagesAreIncludedInLocalHistory() throws {
        let user = try line("response_item", ["id": "image-message", "type": "message", "role": "user", "content": [["type": "input_image", "image_url": "data:image/png;base64,test"]]])
        let entry = try #require(CodexSessionObserver.chatEntry(line: user, index: 0))
        #expect(entry.id == "image-message" && entry.images.count == 1 && entry.text.isEmpty)
    }
    @Test func lateCompletionCannotFinishANewerTurn() throws {
        let header = try line("session_meta", ["id": id, "cwd": "/projects/example"])
        let started = try line("event_msg", ["type": "task_started", "turn_id": "new"])
        let old = try line("event_msg", ["type": "task_complete", "turn_id": "old", "last_agent_message": "Old result"])
        let snapshot = try #require(CodexSessionObserver.parse(header: header, tail: started + old))
        #expect(snapshot.status == "sessionWorking" && snapshot.summary == nil)
    }
    @Test func malformedMetadataAndPartialRecordsCannotFabricateActivity() throws {
        let header = try line("session_meta", ["id": id, "cwd": "/projects/example"])
        let partial = Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}".utf8)
        #expect(CodexSessionObserver.parse(header: header, tail: partial)?.status == "sessionActivityUnknown")
        let tool = try line("response_item", ["type": "function_call", "name": "request_user_input"])
        #expect(CodexSessionObserver.parse(header: header, tail: tool)?.status == "sessionActivityUnknown")
        #expect(CodexSessionObserver.parse(header: try line("session_meta", ["id": "bad", "cwd": "/project"]), tail: Data()) == nil)
    }
    @Test func retainedFinishedSessionsExpireWithoutHidingWorkingSessions() {
        let now = Date(timeIntervalSince1970: 1000)
        var snapshot = CodexSessionObserver.Snapshot(id: id, project: "/project", status: "sessionCompleted")
        snapshot.modifiedAt = now
        snapshot.activityAt = now.addingTimeInterval(-3600)
        #expect(!CodexSessionObserver.isVisible(snapshot, now: now), "Touching an old file must not revive its completed session")
        snapshot.activityAt = now.addingTimeInterval(-10)
        #expect(CodexSessionObserver.isVisible(snapshot, now: now))
        #expect(CodexSessionObserver.isVisible(snapshot, now: now.addingTimeInterval(1700)))
        #expect(!CodexSessionObserver.isVisible(snapshot, now: now.addingTimeInterval(1801)))
        snapshot.status = "sessionWorking"
        #expect(CodexSessionObserver.isVisible(snapshot, now: now.addingTimeInterval(3600)))
        snapshot.status = "sessionActivityUnknown"; snapshot.activityAt = nil
        #expect(!CodexSessionObserver.isVisible(snapshot, now: now.addingTimeInterval(31)))
    }
    @Test func liveOpenFileScanHasStableSessionIdentitiesWithoutReplyRoutes() {
        let found = CodexSessionObserver.scan(records: HostSessionDiscovery.snapshot())
        #expect(Set(found.map(\.id)).count == found.count)
        #expect(found.allSatisfy { $0.sessionID?.ownerInstanceID == "codex-observed" && $0.reason == "sessionReadOnly" })
        print("Live open-file session scan: \(found.count) sessions; no message bodies logged or replies sent")
    }
}
