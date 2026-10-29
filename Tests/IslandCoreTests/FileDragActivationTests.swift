import Testing
@testable import IslandCore

struct FileDragActivationTests {
    @Test func freshFileDragOpensWithoutAnyTopEdgeOrHoverRequirement() {
        var drag = FileDragActivation(idleChangeCount: 10)
        let result1 = drag.update(mouseDown: true, hasFileURLs: true, changeCount: 10)
        #expect(!result1)
        let result2 = drag.update(mouseDown: true, hasFileURLs: true, changeCount: 11)
        #expect(result2)
        let result3 = drag.update(mouseDown: true, hasFileURLs: true, changeCount: 11)
        #expect(result3)
        let result4 = drag.update(mouseDown: false, hasFileURLs: true, changeCount: 11)
        #expect(!result4)
        let result5 = drag.update(mouseDown: true, hasFileURLs: true, changeCount: 11)
        #expect(!result5)
    }
    @Test func textDragsAndIdlePasteboardChangesDoNotOpenDropArea() {
        var drag = FileDragActivation(idleChangeCount: 0)
        let result6 = drag.update(mouseDown: false, hasFileURLs: true, changeCount: 4)
        #expect(!result6)
        let result7 = drag.update(mouseDown: true, hasFileURLs: false, changeCount: 5)
        #expect(!result7)
        let result8 = drag.update(mouseDown: false, hasFileURLs: false, changeCount: 5)
        #expect(!result8)
        let result9 = drag.update(mouseDown: true, hasFileURLs: true, changeCount: 6)
        #expect(result9)
    }
}
