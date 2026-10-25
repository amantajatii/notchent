import Foundation
import ApplicationServices
import AppKit
import IslandCore

struct AgentProbe {
    static let hosts: [(HostKind, String)] = [(.vscode, "Visual Studio Code.app"), (.orca, "Orca.app"), (.terminal, "Utilities/Terminal.app"), (.iterm2, "iTerm.app")]
    func inventory() -> [CapabilityObservation] {
        let roots = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"]
        var observations = Self.hosts.map { host, name in
            let path = roots.map { $0 + "/" + name }.first { FileManager.default.fileExists(atPath: $0) }
            let version = path.flatMap { Bundle(path: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String } ?? "unknown"
            return CapabilityObservation(capability: "hostInstallation.\(host.rawValue)", outcome: path == nil ? .unavailable : .observed, evidence: path.map { "\($0); version \(version). Installation only; sessions unverified." } ?? "Not found in standard application directories; other locations unverified.")
        }
        observations.append(CapabilityObservation(capability: "accessibilityPermission", outcome: AXIsProcessTrusted() ? .observed : .unavailable, evidence: "Read-only AXIsProcessTrusted check. No permission request issued; session accessibility and revocation unverified."))
        let hostIDs = ["com.microsoft.VSCode", "com.stablyai.orca", "com.apple.Terminal", "com.googlecode.iterm2"]
        for app in NSWorkspace.shared.runningApplications where hostIDs.contains(app.bundleIdentifier ?? "") {
            var names: CFArray?
            let result = AXUIElementCopyAttributeNames(AXUIElementCreateApplication(app.processIdentifier), &names)
            observations.append(CapabilityObservation(capability: "accessibilitySurface.\(app.bundleIdentifier ?? "unknown")", outcome: result == .success ? .observed : .unavailable, evidence: result == .success ? "Application AX attribute list accessible (\(names.map { CFArrayGetCount($0) } ?? 0) attributes); values and terminal transcripts not read. Session/prompt routes unverified." : "AX attribute list unavailable (code \(result.rawValue)); no permission request issued."))
        }
        return observations
    }
    func inspect(pid: Int32) -> [CapabilityObservation] {
        let start = SessionIdentityResolver().processStartTime(pid: pid)
        return [CapabilityObservation(capability: "selectedProcessMetadata", outcome: start == nil ? .unavailable : .observed, evidence: start == nil ? "Selected PID unavailable or metadata inaccessible." : "Selected PID \(pid) birth time available; owner and terminal pane unverified. No sendable identity established."),
                CapabilityObservation(capability: "readPrompt", outcome: .unsupported, evidence: "No documented host adapter implemented; no terminal transcript read."),
                CapabilityObservation(capability: "sendResponse", outcome: .unsupported, evidence: "No verified owner/pane route or explicitly approved harmless prompt; no response sent."),
                CapabilityObservation(capability: "openOrigin", outcome: .unsupported, evidence: "No verified origin route implemented.")]
    }
}
