import AppKit
import SwiftUI
import IslandCore

struct SettingsView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var launchAtLogin: LaunchAtLoginStore
    var body: some View {
        VStack(spacing: 0) {
            row(shell.text("language")) {
                Picker(shell.text("language"), selection: $shell.settings.language) {
                    Text("English").tag(IslandLanguage.en)
                    Text("Bahasa Indonesia").tag(IslandLanguage.id)
                }.labelsHidden().frame(width: 180)
            }
            row(shell.text("launchAtLogin")) {
                Toggle(shell.text("launchAtLogin"), isOn: Binding(
                    get: { launchAtLogin.isOn }, set: { launchAtLogin.setEnabled($0) }
                )).labelsHidden().toggleStyle(.switch)
            }
            if launchAtLogin.status == .requiresApproval {
                HStack {
                    Text(shell.text("loginApprovalRequired")).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(shell.text("openLoginItems")) { launchAtLogin.openSystemSettings() }.font(.caption)
                }.padding(.bottom, 8)
            }
            if launchAtLogin.failed {
                Text(shell.text("loginRegistrationError")).font(.caption).foregroundStyle(.red).padding(.bottom, 8)
            }
            row(shell.text("openDelay")) {
                Stepper(value: $shell.settings.openDelayMilliseconds, in: 0...5000, step: 50) {
                    Text("\(shell.settings.openDelayMilliseconds) ms").monospacedDigit()
                }.frame(width: 140)
            }
            row(shell.text("closeDelay")) {
                Stepper(value: $shell.settings.closeDelayMilliseconds, in: 0...10000, step: 100) {
                    Text("\(shell.settings.closeDelayMilliseconds) ms").monospacedDigit()
                }.frame(width: 140)
            }
            row(shell.text("fullScreen")) {
                Picker(shell.text("fullScreen"), selection: $shell.settings.fullScreenPrompts) {
                    Text(shell.text("indicator")).tag(FullScreenPromptPolicy.indicator)
                    Text(shell.text("automatic")).tag(FullScreenPromptPolicy.automatic)
                }.labelsHidden().frame(width: 180)
            }
            row(shell.text("storage")) {
                Picker(shell.text("storage"), selection: $shell.settings.fileStorage) {
                    Text(shell.text("copy")).tag(FileStorageMode.copy)
                    Text(shell.text("reference")).tag(FileStorageMode.reference)
                }.labelsHidden().frame(width: 180)
            }
            if let error = shell.persistenceError { Text(error).font(.caption).foregroundStyle(.red) }
        }.frame(width: 540)
            .onAppear { launchAtLogin.refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
                launchAtLogin.refresh()
            }
    }
    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 8)
            control().font(.system(size: 12))
        }.frame(height: 40)
    }
}
