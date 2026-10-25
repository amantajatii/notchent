import Testing
@testable import IslandCore
struct SessionIdentityTests {
    @Test func testPIDReuseHasDifferentIdentity() {
        #expect(SessionID(ownerInstanceID: "owner", pid: 7, processStartTime: 10, terminalSessionKey: "pane") != SessionID(ownerInstanceID: "owner", pid: 7, processStartTime: 11, terminalSessionKey: "pane"))
    }
    @Test func testTwoPanesInSameProjectDiffer() {
        #expect(SessionID(ownerInstanceID: "owner", pid: 7, processStartTime: 10, terminalSessionKey: "pane-1") != SessionID(ownerInstanceID: "owner", pid: 7, processStartTime: 10, terminalSessionKey: "pane-2"))
    }
    @Test func testUnknownOwnerCannotResolveIdentity() {
        #expect(SessionID.resolve(ownerInstanceID: nil, pid: 7, processStartTime: 10, terminalSessionKey: "pane") == nil)
    }
    @Test func testInvalidComponentsFailClosed() {
        #expect(SessionID.resolve(ownerInstanceID: " ", pid: 7, processStartTime: 10, terminalSessionKey: "pane") == nil)
        #expect(SessionID.resolve(ownerInstanceID: "owner", pid: 0, processStartTime: 10, terminalSessionKey: "pane") == nil)
        #expect(SessionID.resolve(ownerInstanceID: "owner", pid: 7, processStartTime: 0, terminalSessionKey: "pane") == nil)
        #expect(SessionID.resolve(ownerInstanceID: "owner", pid: 7, processStartTime: 10, terminalSessionKey: "") == nil)
    }
    @Test func testOwnerInstancesDiffer() {
        #expect(SessionID(ownerInstanceID: "owner-1", pid: 7, processStartTime: 10, terminalSessionKey: "pane") != SessionID(ownerInstanceID: "owner-2", pid: 7, processStartTime: 10, terminalSessionKey: "pane"))
    }
}
