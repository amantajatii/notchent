import Testing
import Foundation
@testable import IslandCore

struct IslandReducerTests {
    @Test func delaysAndReentry() {
        var s = IslandState()
        #expect(s.mode == .hidden)
        #expect(IslandReducer.reduce(state: &s, event: .pointerEntered) == [.schedule(.open, token: 1, milliseconds: 450)])
        _ = IslandReducer.reduce(state: &s, event: .timer(.open, token: 1))
        #expect(s.mode == .home)
        #expect(IslandReducer.reduce(state: &s, event: .pointerExited) == [.schedule(.close, token: 2, milliseconds: 1000)])
        _ = IslandReducer.reduce(state: &s, event: .pointerEntered)
        _ = IslandReducer.reduce(state: &s, event: .timer(.close, token: 2))
        #expect(s.mode == .home)
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
        #expect(s.mode == .home)
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
