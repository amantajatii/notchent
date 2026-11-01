import ServiceManagement
import Testing
@testable import IslandMac

@MainActor struct LaunchAtLoginTests {
    @Test func initializationOnlyReadsStatusAndToggleUsesSystemState() {
        var systemStatus: SMAppService.Status = .notRegistered
        var requests: [Bool] = []
        let store = LaunchAtLoginStore(readStatus: { systemStatus }, changeRegistration: { enabled in
            requests.append(enabled)
            systemStatus = enabled ? .enabled : .notRegistered
        })
        #expect(!store.isOn && requests.isEmpty)
        store.setEnabled(true)
        #expect(store.isOn && store.status == .enabled && requests == [true])
        store.setEnabled(false)
        #expect(!store.isOn && requests == [true, false])
    }
    @Test func approvalIsShownAsPendingAndCanBeCanceled() {
        var systemStatus: SMAppService.Status = .notRegistered
        let store = LaunchAtLoginStore(readStatus: { systemStatus }, changeRegistration: { enabled in
            systemStatus = enabled ? .requiresApproval : .notRegistered
        })
        store.setEnabled(true)
        #expect(store.isOn && store.status == .requiresApproval && !store.failed)
        store.setEnabled(false)
        #expect(!store.isOn && store.status == .notRegistered)
    }
    @Test func failedRegistrationDoesNotPretendToEnableAndCanBeRetried() {
        var systemStatus: SMAppService.Status = .notRegistered
        var shouldFail = true
        struct Rejected: Error {}
        let store = LaunchAtLoginStore(readStatus: { systemStatus }, changeRegistration: { _ in
            if shouldFail { throw Rejected() }
            systemStatus = .enabled
        })
        store.setEnabled(true)
        #expect(store.failed && !store.isOn)
        shouldFail = false
        store.setEnabled(true)
        #expect(!store.failed && store.isOn)
    }
    @Test func refreshTracksExternalChangesAndFailedUnregisterPreservesState() {
        var systemStatus: SMAppService.Status = .enabled
        struct Rejected: Error {}
        let store = LaunchAtLoginStore(readStatus: { systemStatus }, changeRegistration: { _ in throw Rejected() })
        store.setEnabled(false)
        #expect(store.failed && store.isOn)
        systemStatus = .requiresApproval
        store.refresh()
        #expect(store.status == .requiresApproval)
        systemStatus = .notRegistered
        store.refresh()
        #expect(!store.isOn)
    }
}
