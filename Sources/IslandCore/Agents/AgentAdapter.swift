import Foundation

/// A CLI-local request ID is meaningful only within its exact process/owner/pane identity.
public struct PromptID: Hashable, Sendable {
    public let sessionID: SessionID
    public let localRequestID: String
    public init(sessionID: SessionID, localRequestID: String) {
        self.sessionID = sessionID; self.localRequestID = localRequestID
    }
}
public struct PromptChoice: Equatable, Sendable {
    public let id: String
    public let text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}
public struct AgentPrompt: Equatable, Sendable {
    public let id: PromptID
    public var sessionID: SessionID { id.sessionID }
    public let revision: UInt64
    public let text: String
    public let choices: [PromptChoice]
    public let acceptsText: Bool
    public init(id: PromptID, revision: UInt64, text: String, choices: [PromptChoice], acceptsText: Bool) {
        self.id = id; self.revision = revision; self.text = text; self.choices = choices; self.acceptsText = acceptsText
    }
}
public enum AgentResponse: Equatable, Sendable { case choice(String), text(String) }
public enum ResponseReceipt: Equatable, Sendable { case sent, confirmed, rejected, unknown }
public struct AgentRoute: Sendable {
    public let sessionID: SessionID
    public let kind: AgentKind
    public let capabilities: AgentCapabilities
    public let permissionGranted: Bool
    public init(sessionID: SessionID, kind: AgentKind, capabilities: AgentCapabilities, permissionGranted: Bool) {
        self.sessionID = sessionID; self.kind = kind; self.capabilities = capabilities; self.permissionGranted = permissionGranted
    }
}
public enum AgentEvent: Sendable {
    case route(AgentRoute), prompt(AgentPrompt, kind: AgentKind), resolved(PromptID, kind: AgentKind), exited(SessionID)
}
public enum AgentRoutingError: Error, Equatable { case missingPrompt, notFIFOHead, staleRevision, invalidResponse, unavailable, identityChanged, permissionRevoked, deliveryAlreadyAttempted }
public protocol AgentAdapter: Sendable {
    func events() -> AsyncStream<AgentEvent>
    /// Must freshly validate owner, pane, process birth and permission. Never returns a cached route.
    func validate(sessionID: SessionID) async throws -> AgentRoute
    func respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt
    func openOrigin(sessionID: SessionID) async throws
}
