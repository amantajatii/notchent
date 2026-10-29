import SwiftUI
import IslandCore

struct SettingsView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        VStack(spacing: 0) {
            row(shell.text("language")) {
                Picker(shell.text("language"), selection: $shell.settings.language) {
                    Text("English").tag(IslandLanguage.en)
                    Text("Bahasa Indonesia").tag(IslandLanguage.id)
                }.labelsHidden().frame(width: 180)
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
    }
    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 8)
            control().font(.system(size: 12))
        }.frame(height: 40)
    }
}
