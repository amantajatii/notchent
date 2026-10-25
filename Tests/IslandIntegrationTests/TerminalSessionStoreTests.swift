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
        #expect(firstView.view != nil)
        #expect(store.lifecycle.contains(first))
        #expect(store.lifecycle.contains(second))
        #expect(store.isRunning(second))
        #expect(kill(second.pid, 0) == 0)
        for _ in 0..<30 {
            if kill(first.pid, 0) == -1 && errno == ESRCH { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(kill(first.pid, 0) == -1 && errno == ESRCH)
        for _ in 0..<20 {
            if !store.lifecycle.contains(first) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!store.lifecycle.contains(first))
        #expect(firstView.view == nil)
    }

    @Test func closeEscalatesRetainedTerminalIgnoringTERMWithoutTouchingOtherSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-close-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TerminalSessionStore()
        let first = try store.create(directory: directory)
        let second = try store.create(directory: directory)
        defer { store.close(first); store.close(second) }
        let retained = store.view(for: first) as! LocalProcessTerminalView
        let childPIDFile = directory.appendingPathComponent("foreground.pid")
        let command = "trap '' TERM; sh -c 'echo $$ > \"\(childPIDFile.path)\"; trap \"\" TERM; exec sleep 60'\n"
        retained.process.send(data: ArraySlice(command.utf8))
        for _ in 0..<30 {
            if FileManager.default.fileExists(atPath: childPIDFile.path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let childPID = Int32(try String(contentsOf: childPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        #expect(kill(childPID, 0) == 0)
        store.close(first)
        #expect(store.hasRunningOwnedSessions)
        for _ in 0..<40 {
            if kill(first.pid, 0) == -1 && errno == ESRCH { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(kill(first.pid, 0) == -1 && errno == ESRCH)
        #expect(kill(childPID, 0) == -1 && errno == ESRCH)
        #expect(kill(second.pid, 0) == 0)
        #expect(store.isRunning(second))
        _ = retained
    }

    @Test func identityMismatchRejectsEscalation() async throws {
        let store = TerminalSessionStore()
        let id = try store.create(directory: FileManager.default.temporaryDirectory)
        let retained = store.view(for: id) as! LocalProcessTerminalView
        retained.process.send(data: ArraySlice("trap '' TERM; sleep 60\n".utf8))
        try await Task.sleep(for: .milliseconds(250))
        let realBirthTime = store.processBirthTime
        store.processBirthTime = { _ in id.processStartTime + 1 }
        store.close(id)
        try await Task.sleep(for: .milliseconds(800))
        #expect(kill(id.pid, 0) == 0)
        #expect(store.hasRunningOwnedSessions)
        store.processBirthTime = realBirthTime
        store.escalateIfStillOwned(id)
        for _ in 0..<30 {
            if kill(id.pid, 0) == -1 && errno == ESRCH { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(kill(id.pid, 0) == -1 && errno == ESRCH)
        _ = retained
    }

    @Test func quitBarrierWaitsForOwnedProcessExitWithRetainedView() async throws {
        let store = TerminalSessionStore()
        let id = try store.create(directory: FileManager.default.temporaryDirectory)
        let retained = store.view(for: id) as! LocalProcessTerminalView
        retained.process.send(data: ArraySlice("trap '' TERM; sleep 60\n".utf8))
        try await Task.sleep(for: .milliseconds(250))
        let completed = await store.closeAllAndWait()
        #expect(completed)
        #expect(!store.hasRunningOwnedSessions)
        #expect(kill(id.pid, 0) == -1 && errno == ESRCH)
        _ = retained
    }
}
