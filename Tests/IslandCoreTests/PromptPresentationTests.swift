import Testing
@testable import IslandCore

struct PromptPresentationTests {
    @Test func bannerPreservesTerminalAndDraft() {
        var s = IslandState()
        _ = IslandReducer.reduce(state: &s, event: .show(.terminal))
        _ = IslandReducer.reduce(state: &s, event: .inputChanged(true))
        _ = IslandReducer.reduce(state: &s, event: .pendingChanged(1))
        #expect(s.mode == .feature(.terminal))
        #expect(s.showsPromptBanner)
        _ = IslandReducer.reduce(state: &s, event: .openPrompt)
        #expect(s.mode == .prompt)
    }
    @Test func fullscreenOnlyIndicator() {
        var s = IslandState()
        _ = IslandReducer.reduce(state: &s, event: .fullScreenChanged(true))
        _ = IslandReducer.reduce(state: &s, event: .pendingChanged(1))
        #expect(s.mode == .hidden)
        #expect(s.showsPendingAffordance)
    }
}

extension PromptPresentationTests {
    @Test func idleTerminalStillBannersAndReturnsAfterExplicitPrompt() {
        var state = IslandState()
        _ = IslandReducer.reduce(state: &state, event: .show(.terminal))
        _ = IslandReducer.reduce(state: &state, event: .pendingChanged(2))
        #expect(state.mode == .feature(.terminal)); #expect(state.showsPromptBanner)
        _ = IslandReducer.reduce(state: &state, event: .openPrompt)
        _ = IslandReducer.reduce(state: &state, event: .closePrompt)
        #expect(state.mode == .feature(.terminal)); #expect(state.pendingCount == 2)
        _ = IslandReducer.reduce(state: &state, event: .openPrompt)
        _ = IslandReducer.reduce(state: &state, event: .pendingChanged(0))
        #expect(state.mode == .feature(.terminal))
    }
}
