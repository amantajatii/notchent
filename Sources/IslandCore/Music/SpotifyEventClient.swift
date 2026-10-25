import AppKit
import ApplicationServices

/// Native events carry only a captured process address: there is no bundle/name launch target.
@MainActor
public final class SpotifyEventClient {
    private let application: NSRunningApplication
    public let pid: pid_t
    private let launchDate: Date?

    public init?(application: NSRunningApplication) {
        guard application.bundleIdentifier == "com.spotify.client", !application.isTerminated else { return nil }
        self.application = application
        pid = application.processIdentifier
        launchDate = application.launchDate
    }

    public static func processTarget(pid: pid_t) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(processIdentifier: pid)
    }

    public static func processMatches(capturedPID: pid_t, capturedLaunch: Date?, currentPID: pid_t?, currentLaunch: Date?, terminated: Bool) -> Bool {
        !terminated && capturedPID > 0 && capturedPID == currentPID && capturedLaunch != nil && capturedLaunch == currentLaunch
    }

    private var stillRunning: Bool {
        let current = NSRunningApplication(processIdentifier: pid)
        return Self.processMatches(capturedPID: pid, capturedLaunch: launchDate, currentPID: current?.processIdentifier,
                                   currentLaunch: current?.launchDate, terminated: application.isTerminated || current?.bundleIdentifier != "com.spotify.client")
    }

    public func permission() -> OSStatus {
        guard stillRunning else { return -600 }
        return AEDeterminePermissionToAutomateTarget(Self.processTarget(pid: pid).aeDesc, typeWildCard, typeWildCard, false)
    }

    public static func property(_ code: AEKeyword, container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let object = NSAppleEventDescriptor.record()
        object.setDescriptor(NSAppleEventDescriptor(typeCode: UInt32(typeProperty)), forKeyword: UInt32(keyAEDesiredClass))
        object.setDescriptor(NSAppleEventDescriptor(enumCode: UInt32(formPropertyID)), forKeyword: UInt32(keyAEKeyForm))
        object.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: UInt32(keyAEKeyData))
        object.setDescriptor(container, forKeyword: UInt32(keyAEContainer))
        return object.coerce(toDescriptorType: UInt32(typeObjectSpecifier))!
    }

    public func read(_ property: AEKeyword, currentTrack: Bool = false) throws -> NSAppleEventDescriptor {
        let container = currentTrack ? Self.property(0x7054726B) : NSAppleEventDescriptor.null() // pTrk
        return try send(eventClass: UInt32(kAECoreSuite), eventID: UInt32(kAEGetData), direct: Self.property(property, container: container))
    }

    public func control(_ name: String) throws -> NSAppleEventDescriptor {
        let commands: [String: AEEventID] = ["play": 0x506C6179, "pause": 0x50617573, "next track": 0x4E657874, "previous track": 0x50726576]
        guard let command = commands[name] else { throw NSError(domain: NSOSStatusErrorDomain, code: -1708) }
        return try send(eventClass: 0x73706679, eventID: command) // spfy
    }

    private func send(eventClass: AEEventClass, eventID: AEEventID, direct: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        guard stillRunning else { throw NSError(domain: NSOSStatusErrorDomain, code: -600) }
        let consent = permission()
        guard consent == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(consent)) }
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: Self.processTarget(pid: pid), returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(direct, forKeyword: keyDirectObject) }
        // Consent is preflighted without prompting; the target is instructed not to interact.
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        guard stillRunning else { throw NSError(domain: NSOSStatusErrorDomain, code: -600) }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
    }
}
