import Foundation

/// An identity is a routing candidate, never permission to send a response.
public struct SessionID: Hashable, Codable, Sendable {
    public let ownerInstanceID: String
    public let pid: Int32
    /// Process birth time in microseconds since Unix epoch; not observation time.
    public let processStartTime: UInt64
    public let terminalSessionKey: String

    public init(ownerInstanceID: String, pid: Int32, processStartTime: UInt64, terminalSessionKey: String) {
        self.ownerInstanceID = ownerInstanceID
        self.pid = pid
        self.processStartTime = processStartTime
        self.terminalSessionKey = terminalSessionKey
    }

    public static func resolve(ownerInstanceID: String?, pid: Int32, processStartTime: UInt64, terminalSessionKey: String?) -> SessionID? {
        guard let owner = ownerInstanceID, !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key = terminalSessionKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pid > 0, processStartTime > 0 else { return nil }
        return SessionID(ownerInstanceID: owner, pid: pid, processStartTime: processStartTime, terminalSessionKey: key)
    }
}

public enum AgentKind: String, Codable, CaseIterable, Sendable { case codex, antigravity, claudeCode, ohMyPi }
public enum HostKind: String, Codable, CaseIterable, Sendable { case vscode, orca, terminal, iterm2 }
public enum ProbeOutcome: String, Codable, Sendable { case observed, unsupported, unavailable, denied }
public struct AgentCapabilities: Codable, Sendable {
    public let discovery: Bool
    public let readPrompt: Bool
    public let sendResponse: Bool
    public let openOrigin: Bool
    public init(discovery: Bool = false, readPrompt: Bool = false, sendResponse: Bool = false, openOrigin: Bool = false) {
        self.discovery = discovery; self.readPrompt = readPrompt; self.sendResponse = sendResponse; self.openOrigin = openOrigin
    }
}
public struct CapabilityObservation: Codable, Sendable {
    public let sessionID: SessionID?
    public let capability: String
    public let outcome: ProbeOutcome
    public let evidence: String
    public init(sessionID: SessionID? = nil, capability: String, outcome: ProbeOutcome, evidence: String) {
        self.sessionID = sessionID; self.capability = capability; self.outcome = outcome; self.evidence = evidence
    }
}
