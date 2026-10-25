import Testing
@testable import IslandCore

struct TerminalLifecycleTests {
    private func id(_ pid: Int32) -> SessionID {
        SessionID(ownerInstanceID: "app", pid: pid, processStartTime: UInt64(pid), terminalSessionKey: "owned-\(pid)")
    }

    @Test func hideAndSwitchKeepOwnedSessions() {
        var lifecycle = TerminalLifecycle()
        let first = id(100), second = id(101)
        lifecycle.open(first); lifecycle.open(second)
        lifecycle.featureHidden(); lifecycle.featureSwitched()
        #expect(lifecycle.contains(first))
        #expect(lifecycle.contains(second))
        #expect(lifecycle.hasRunningOwnedSessions)
    }

    @Test func explicitCloseTargetsOnlySelectedSession() {
        var lifecycle = TerminalLifecycle()
        let first = id(100), second = id(101)
        lifecycle.open(first); lifecycle.open(second)
        let didClose = lifecycle.close(first)
        #expect(didClose)
        #expect(!lifecycle.contains(first))
        #expect(lifecycle.contains(second))
        let closedAgain = lifecycle.close(first)
        #expect(!closedAgain)
    }

    @Test func quitRequiresConfirmationOnlyForRunningOwnedSessions() {
        var lifecycle = TerminalLifecycle()
        #expect(!lifecycle.shouldConfirmQuit)
        let session = id(100)
        lifecycle.open(session)
        #expect(lifecycle.shouldConfirmQuit)
        lifecycle.processExited(session)
        #expect(!lifecycle.shouldConfirmQuit)
        #expect(lifecycle.contains(session))
    }
}
