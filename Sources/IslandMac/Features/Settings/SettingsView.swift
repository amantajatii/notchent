import SwiftUI
import IslandCore

struct SettingsView: View {
    @ObservedObject var shell: IslandShell
    var body: some View {
        Form {
            Picker(shell.text("language"), selection: $shell.settings.language) {
                Text("English").tag(IslandLanguage.en)
                Text("Bahasa Indonesia").tag(IslandLanguage.id)
            }
            Stepper(value: $shell.settings.openDelayMilliseconds, in: 0...5000, step: 50) {
                Text("\(shell.text("openDelay")): \(shell.settings.openDelayMilliseconds) ms")
            }
            Stepper(value: $shell.settings.closeDelayMilliseconds, in: 0...10000, step: 100) {
                Text("\(shell.text("closeDelay")): \(shell.settings.closeDelayMilliseconds) ms")
            }
            Picker(shell.text("fullScreen"), selection: $shell.settings.fullScreenPrompts) {
                Text(shell.text("indicator")).tag(FullScreenPromptPolicy.indicator)
                Text(shell.text("automatic")).tag(FullScreenPromptPolicy.automatic)
            }
            Picker(shell.text("storage"), selection: $shell.settings.fileStorage) {
                Text(shell.text("copy")).tag(FileStorageMode.copy)
                Text(shell.text("reference")).tag(FileStorageMode.reference)
            }
            if let error = shell.persistenceError { Text(error).foregroundStyle(.red) }
        }.formStyle(.grouped).frame(width: 540)
    }
}
