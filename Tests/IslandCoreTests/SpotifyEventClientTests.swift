import Foundation
import ApplicationServices
import Testing
@testable import IslandCore

@MainActor struct SpotifyEventClientTests {
    @Test func addressContainsOnlyCapturedPID() {
        let target = SpotifyEventClient.processTarget(pid: 12345)
        #expect(target.descriptorType == typeKernelProcessID)
        var expected: Int32 = 12345
        #expect(target.data == Data(bytes: &expected, count: MemoryLayout<Int32>.size))
    }
    @Test func disappearanceOrPIDReuseIsUnavailable() {
        let birth = Date(timeIntervalSince1970: 10)
        #expect(SpotifyEventClient.processMatches(capturedPID: 12, capturedLaunch: birth, currentPID: 12, currentLaunch: birth, terminated: false))
        #expect(!SpotifyEventClient.processMatches(capturedPID: 12, capturedLaunch: birth, currentPID: nil, currentLaunch: nil, terminated: true))
        #expect(!SpotifyEventClient.processMatches(capturedPID: 12, capturedLaunch: birth, currentPID: 12, currentLaunch: birth.addingTimeInterval(1), terminated: false))
        #expect(!SpotifyEventClient.processMatches(capturedPID: 12, capturedLaunch: nil, currentPID: 12, currentLaunch: nil, terminated: false))
    }
}
