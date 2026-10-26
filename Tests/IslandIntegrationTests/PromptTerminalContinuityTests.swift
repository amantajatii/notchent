import AppKit
import Foundation
import Testing
import IslandCore
import SwiftTerm
@testable import IslandMac

@MainActor struct PromptTerminalContinuityTests {
    @Test func realPTYDraftSurvivesBannerPromptAndReturn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-prompt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TerminalSessionStore()
        let id = try store.create(directory: directory)
        let view = try #require(store.view(for: id) as? LocalProcessTerminalView)
        let proof = directory.appendingPathComponent("draft.txt")
        // Draft remains in the actual shell line editor, not a replacement SwiftUI field.
        view.process.send(data: ArraySlice("printf 'draft-preserved' > '\(proof.path)'".utf8))
        try await Task.sleep(for: .milliseconds(250))
        var state = IslandState()
        _ = IslandReducer.reduce(state: &state, event: .show(.terminal))
        _ = IslandReducer.reduce(state: &state, event: .inputChanged(true))
        _ = IslandReducer.reduce(state: &state, event: .pendingChanged(1))
        #expect(state.mode == .feature(.terminal)); #expect(state.inputActive)
        #expect(!FileManager.default.fileExists(atPath: proof.path))
        _ = IslandReducer.reduce(state: &state, event: .openPrompt)
        _ = IslandReducer.reduce(state: &state, event: .closePrompt)
        #expect(state.mode == .feature(.terminal))
        #expect(store.selectedID == id); #expect(store.view(for: id) === view)
        view.process.send(data: ArraySlice("\n".utf8))
        for _ in 0..<30 {
            if FileManager.default.fileExists(atPath: proof.path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try String(contentsOf: proof, encoding: .utf8) == "draft-preserved")
        #expect(await store.closeAllAndWait())
    }
}
