import AppKit
import SwiftUI
import IslandCore

struct SettingsView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var launchAtLogin: LaunchAtLoginStore
    private let controlWidth: CGFloat = 170

    var body: some View {
        VStack(spacing: IslandDesign.gap) {
            generalSection
            panelSection
            IslandFormSection {
                settingsRow(shell.text("storage"), symbol: "externaldrive.fill", tint: .gray) {
                    Picker(shell.text("storage"), selection: $shell.settings.fileStorage) {
                        Text(shell.text("copy")).tag(FileStorageMode.copy)
                        Text(shell.text("reference")).tag(FileStorageMode.reference)
                    }.labelsHidden().frame(width: controlWidth)
                }
            }
            UpdateSection(store: shell.updates, shell: shell)
            if let error = shell.persistenceError { Text(error).font(IslandDesign.caption).foregroundStyle(IslandDesign.danger) }
        }
        .font(IslandDesign.body)
        .frame(width: IslandDesign.contentWidth)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var generalSection: some View {
        IslandFormSection {
            settingsRow(shell.text("language"), symbol: "globe", tint: .blue) {
                Picker(shell.text("language"), selection: $shell.settings.language) {
                    Text("English").tag(IslandLanguage.en)
                    Text("Bahasa Indonesia").tag(IslandLanguage.id)
                }.labelsHidden().frame(width: controlWidth)
            }
            IslandFormDivider().padding(.leading, 42)
            settingsRow(shell.text("launchAtLogin"), symbol: "power", tint: IslandDesign.success, subtitle: loginSubtitle) {
                HStack(spacing: 10) {
                    if launchAtLogin.status == .requiresApproval {
                        Button(shell.text("openLoginItems")) { launchAtLogin.openSystemSettings() }
                            .buttonStyle(IslandPillButtonStyle(emphasis: .tinted, tint: .blue))
                    }
                    Toggle(shell.text("launchAtLogin"), isOn: Binding(
                        get: { launchAtLogin.isOn }, set: { launchAtLogin.setEnabled($0) }
                    )).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(IslandDesign.success)
                }
            }
        }
    }

    private var loginSubtitle: String? {
        if launchAtLogin.failed { return shell.text("loginRegistrationError") }
        if launchAtLogin.status == .requiresApproval { return shell.text("loginApprovalRequired") }
        return nil
    }

    private var panelSection: some View {
        IslandFormSection {
            settingsRow(shell.text("openDelay"), symbol: "timer", tint: IslandDesign.warning) {
                Stepper(value: $shell.settings.openDelayMilliseconds, in: 0...5000, step: 50) {
                    Text("\(shell.settings.openDelayMilliseconds) ms").monospacedDigit()
                }.controlSize(.small)
            }
            IslandFormDivider().padding(.leading, 42)
            settingsRow(shell.text("closeDelay"), symbol: "timer", tint: IslandDesign.warning) {
                Stepper(value: $shell.settings.closeDelayMilliseconds, in: 0...10000, step: 100) {
                    Text("\(shell.settings.closeDelayMilliseconds) ms").monospacedDigit()
                }.controlSize(.small)
            }
            IslandFormDivider().padding(.leading, 42)
            settingsRow(shell.text("fullScreen"), symbol: "rectangle.inset.filled", tint: .gray) {
                Picker(shell.text("fullScreen"), selection: $shell.settings.fullScreenPrompts) {
                    Text(shell.text("indicator")).tag(FullScreenPromptPolicy.indicator)
                    Text(shell.text("automatic")).tag(FullScreenPromptPolicy.automatic)
                }.labelsHidden().frame(width: controlWidth)
            }
        }
    }

    private func settingsRow<Control: View>(_ title: String, symbol: String, tint: Color, subtitle: String? = nil,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: -6) {
            IslandGlyph(symbol: symbol, tint: tint, size: 26, shape: .squircle).padding(.leading, IslandDesign.cardPadding)
            IslandFormRow(title, subtitle: subtitle, control: control)
        }
    }
}
