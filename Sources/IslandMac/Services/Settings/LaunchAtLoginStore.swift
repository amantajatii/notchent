import Combine
import ServiceManagement

@MainActor final class LaunchAtLoginStore: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var failed = false
    private let readStatus: () -> SMAppService.Status
    private let changeRegistration: (Bool) throws -> Void

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         changeRegistration: @escaping (Bool) throws -> Void = { enabled in
             if enabled { try SMAppService.mainApp.register() }
             else { try SMAppService.mainApp.unregister() }
         }) {
        self.readStatus = readStatus
        self.changeRegistration = changeRegistration
        status = readStatus()
    }
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status = readStatus() }
    func setEnabled(_ enabled: Bool) {
        failed = false
        refresh()
        guard enabled != isOn else { return }
        do { try changeRegistration(enabled) }
        catch { failed = true }
        refresh()
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
