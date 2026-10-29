import Testing
import Foundation
@testable import IslandCore

struct IslandReducerTests {
    @Test func explicitOpenGivesTimeToReachPanelThenRestoresHoverDelay() {
        var state = IslandState()
        state.settings.closeDelayMilliseconds = 300
        let effects = IslandReducer.reduce(state: &state, event: .reveal(.home))
        let revealToken = state.generation
        #expect(state.mode == .home)
        #expect(effects == [.schedule(.close, token: revealToken, milliseconds: 5000)])
        _ = IslandReducer.reduce(state: &state, event: .pointerEntered)
        _ = IslandReducer.reduce(state: &state, event: .timer(.close, token: revealToken))
        #expect(state.mode == .home)
        #expect(IslandReducer.reduce(state: &state, event: .pointerExited) == [.schedule(.close, token: state.generation, milliseconds: 300)])
    }
    @Test func explicitOpenStillClosesAndNeverShortensLongUserDelay() {
        var state = IslandState()
        state.settings.closeDelayMilliseconds = 8000
        #expect(IslandReducer.reduce(state: &state, event: .reveal(.settings)) == [.schedule(.close, token: 1, milliseconds: 8000)])
        _ = IslandReducer.reduce(state: &state, event: .hide)
        #expect(state.mode == .hidden)
        _ = IslandReducer.reduce(state: &state, event: .reveal(.home))
        _ = IslandReducer.reduce(state: &state, event: .timer(.close, token: state.generation))
        #expect(state.mode == .hidden)
    }
    @Test func delaysAndReentry() {
        var s = IslandState()
        #expect(s.mode == .hidden)
        #expect(IslandReducer.reduce(state: &s, event: .pointerEntered) == [.schedule(.open, token: 1, milliseconds: 450)])
        _ = IslandReducer.reduce(state: &s, event: .timer(.open, token: 1))
        #expect(s.mode == .mini)
        #expect(IslandReducer.reduce(state: &s, event: .pointerExited) == [.schedule(.close, token: 2, milliseconds: 1000)])
        _ = IslandReducer.reduce(state: &s, event: .pointerEntered)
        _ = IslandReducer.reduce(state: &s, event: .timer(.close, token: 2))
        #expect(s.mode == .mini)
    }
    @Test func staleCloseDoesNotHideReopenedPanel() {
        var s = IslandState()
        _ = IslandReducer.reduce(state: &s, event: .show(.terminal))
        _ = IslandReducer.reduce(state: &s, event: .pointerExited)
        let token = s.generation
        _ = IslandReducer.reduce(state: &s, event: .show(.music))
        _ = IslandReducer.reduce(state: &s, event: .timer(.close, token: token))
        #expect(s.mode == .feature(.music))
    }
    @Test func droppedFilesStayOpenUntilDismissedOrDraggedAgain() {
        var state = IslandState()
        _ = IslandReducer.reduce(state: &state, event: .dragChanged(true))
        _ = IslandReducer.reduce(state: &state, event: .dragChanged(false))
        _ = IslandReducer.reduce(state: &state, event: .filesDropped)
        #expect(state.mode == .feature(.files))
        #expect(IslandReducer.reduce(state: &state, event: .pointerExited).isEmpty)
        _ = IslandReducer.reduce(state: &state, event: .hide)
        #expect(state.mode == .hidden)
        _ = IslandReducer.reduce(state: &state, event: .filesDropped)
        _ = IslandReducer.reduce(state: &state, event: .dragChanged(true))
        _ = IslandReducer.reduce(state: &state, event: .dragChanged(false))
        #expect(state.mode == .hidden)
        _ = IslandReducer.reduce(state: &state, event: .filesDropped)
        _ = IslandReducer.reduce(state: &state, event: .shelfDragEnded)
        #expect(state.mode == .hidden)
    }
    @Test func dragAndInputLocks() {
        var s = IslandState()
        _ = IslandReducer.reduce(state: &s, event: .dragChanged(true))
        #expect(s.mode == .drop)
        _ = IslandReducer.reduce(state: &s, event: .pointerExited)
        _ = IslandReducer.reduce(state: &s, event: .timer(.close, token: s.generation))
        #expect(s.mode == .drop)
        _ = IslandReducer.reduce(state: &s, event: .dragChanged(false))
        #expect(s.mode == .hidden)
        _ = IslandReducer.reduce(state: &s, event: .show(.terminal))
        _ = IslandReducer.reduce(state: &s, event: .inputChanged(true))
        #expect(IslandReducer.reduce(state: &s, event: .pointerExited).isEmpty)
        _ = IslandReducer.reduce(state: &s, event: .pendingChanged(2))
        #expect(s.mode == .feature(.terminal))
        #expect(s.pendingCount == 2)
    }
    @Test func fullscreenAndPromptOnly() {
        var s = IslandState()
        _ = IslandReducer.reduce(state: &s, event: .fullScreenChanged(true))
        _ = IslandReducer.reduce(state: &s, event: .pendingChanged(1))
        #expect(s.mode == .hidden && s.pendingCount == 1)
        _ = IslandReducer.reduce(state: &s, event: .openPrompt)
        #expect(s.mode == .prompt)
        var normal = IslandState()
        _ = IslandReducer.reduce(state: &normal, event: .pendingChanged(1))
        #expect(normal.mode == .prompt)
    }
}

struct IslandShellRegressionTests {
    @Test func unrelatedUpdatesPreserveOpenDeadline() {
        var s = IslandState()
        let effects = IslandReducer.reduce(state: &s, event: .pointerEntered)
        let token = s.generation
        #expect(IslandReducer.reduce(state: &s, event: .pendingChanged(0)).isEmpty)
        #expect(IslandReducer.reduce(state: &s, event: .fullScreenChanged(true)).isEmpty)
        #expect(s.generation == token)
        #expect(effects == [.schedule(.open, token: token, milliseconds: 450)])
        _ = IslandReducer.reduce(state: &s, event: .timer(.open, token: token))
        #expect(s.mode == .mini)
    }
    @Test func unrelatedUpdatesPreserveCloseDeadline() {
        var s = IslandState(); s.pointerInside = true
        _ = IslandReducer.reduce(state: &s, event: .show(.home))
        _ = IslandReducer.reduce(state: &s, event: .pointerExited)
        let token = s.generation
        #expect(IslandReducer.reduce(state: &s, event: .pendingChanged(0)).isEmpty)
        #expect(IslandReducer.reduce(state: &s, event: .fullScreenChanged(true)).isEmpty)
        #expect(s.generation == token)
        _ = IslandReducer.reduce(state: &s, event: .timer(.close, token: token))
        #expect(s.mode == .hidden)
    }
    @Test func menuRoutesOutsideScheduleDismissal() {
        for feature in [IslandFeature.home, .settings] {
            var s = IslandState()
            let effects = IslandReducer.reduce(state: &s, event: .show(feature))
            #expect(effects == [.schedule(.close, token: s.generation, milliseconds: 1000)])
            _ = IslandReducer.reduce(state: &s, event: .timer(.close, token: s.generation))
            #expect(s.mode == .hidden)
        }
    }
    @Test func fullScreenPendingRemainsReachableOnHome() {
        var s = IslandState(); s.pointerInside = true
        _ = IslandReducer.reduce(state: &s, event: .show(.home))
        _ = IslandReducer.reduce(state: &s, event: .fullScreenChanged(true))
        _ = IslandReducer.reduce(state: &s, event: .pendingChanged(2))
        #expect(s.mode == .home)
        #expect(s.showsPendingAffordance)
        _ = IslandReducer.reduce(state: &s, event: .openPrompt)
        #expect(s.mode == .prompt)
    }
    @Test func unknownFullScreenObservationIsConservative() {
        #expect(FullScreenAssessment.isFullScreen(windowBounds: nil, screen: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        #expect(FullScreenAssessment.isFullScreen(windowBounds: [], screen: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        #expect(FullScreenAssessment.isFullScreen(windowBounds: [CGRect(x: 0, y: 0, width: 1440, height: 900)], screen: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        #expect(!FullScreenAssessment.isFullScreen(windowBounds: [CGRect(x: 120, y: 100, width: 700, height: 500)], screen: CGRect(x: 0, y: 0, width: 1440, height: 900)))
    }
}

struct AgentCompletionPresentationTests {
    @Test func completionRevealsSmallNoticeAndExpires() {
        var state = IslandState()
        let effects = IslandReducer.reduce(state: &state, event: .agentCompleted)
        #expect(state.mode == .completion)
        #expect(effects == [.schedule(.close, token: state.generation, milliseconds: 5000)])
        _ = IslandReducer.reduce(state: &state, event: .timer(.close, token: state.generation))
        #expect(state.mode == .hidden)
    }
    @Test func completionDoesNotInterruptInputPromptsOrAnOpenPage() {
        for mode: IslandMode in [.feature(.agents), .feature(.terminal), .prompt, .drop, .home] {
            var state = IslandState(); state.mode = mode
            #expect(IslandReducer.reduce(state: &state, event: .agentCompleted).isEmpty)
            #expect(state.mode == mode)
        }
        var typing = IslandState(); typing.inputActive = true
        #expect(IslandReducer.reduce(state: &typing, event: .agentCompleted).isEmpty)
        var pending = IslandState(); pending.pendingCount = 1
        #expect(IslandReducer.reduce(state: &pending, event: .agentCompleted).isEmpty)
    }
    @Test func newQuestionTakesPriorityAndOldCloseCannotHideItAfterHover() {
        var state = IslandState()
        _ = IslandReducer.reduce(state: &state, event: .agentCompleted)
        let old = state.generation
        _ = IslandReducer.reduce(state: &state, event: .pointerEntered)
        _ = IslandReducer.reduce(state: &state, event: .pendingChanged(1))
        _ = IslandReducer.reduce(state: &state, event: .timer(.close, token: old))
        #expect(state.mode == .prompt)
    }
}

struct PendingPromptLifetimeTests {
    @Test func questionStaysVisibleOutsideHoverUntilExplicitDismissal() {
        var state = IslandState()
        _ = IslandReducer.reduce(state: &state, event: .reveal(.home))
        let staleClose = state.generation
        _ = IslandReducer.reduce(state: &state, event: .pendingChanged(1))
        #expect(state.mode == .prompt && state.scheduledTransition == nil)
        #expect(IslandReducer.reduce(state: &state, event: .pointerExited).isEmpty)
        _ = IslandReducer.reduce(state: &state, event: .timer(.close, token: staleClose))
        #expect(state.mode == .prompt)
        _ = IslandReducer.reduce(state: &state, event: .closePrompt)
        #expect(state.mode == .hidden && state.pendingCount == 1)
    }
}
