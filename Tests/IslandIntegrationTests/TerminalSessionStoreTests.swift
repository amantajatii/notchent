import AppKit
import Darwin
import Foundation
import Testing
import IslandCore
import SwiftTerm
@testable import IslandMac

private final class WeakViewReference {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}

@MainActor struct TerminalSessionStoreTests {
    @Test func ownedPTYSurvivesPresentationAndCloseTargetsOnlyOneProcess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-terminal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TerminalSessionStore()
        let first = try store.create(directory: directory)
        let second = try store.create(directory: directory)
        defer { store.close(first); store.close(second) }

        let firstView = WeakViewReference(store.view(for: first))
        store.selectedID = first
        store.selectedID = second
        store.selectedID = first
        #expect(store.view(for: first) === firstView.view)
        #expect(store.hasRunningOwnedSessions)
        #expect(kill(first.pid, 0) == 0)
        #expect(kill(second.pid, 0) == 0)

        let proof = directory.appendingPathComponent("command-ran.txt")
        let command = "printf 'owned terminal works' > '\(proof.path)'\n"
        (firstView.view as? LocalProcessTerminalView)?.process.send(data: ArraySlice(command.utf8))
        for _ in 0..<30 {
            if FileManager.default.fileExists(atPath: proof.path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try String(contentsOf: proof, encoding: .utf8) == "owned terminal works")

        store.close(first)
        #expect(firstView.view == nil)
        #expect(store.lifecycle.contains(second))
        #expect(store.isRunning(second))
        #expect(kill(second.pid, 0) == 0)
        for _ in 0..<30 {
            if kill(first.pid, 0) == -1 && errno == ESRCH { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(kill(first.pid, 0) == -1 && errno == ESRCH)
    }
}
