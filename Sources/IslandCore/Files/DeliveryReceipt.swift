/// A confirmed receipt requires acknowledgement beyond native drag acceptance.
public enum DeliveryReceipt: String, Codable, Sendable {
    case confirmed, cancelled, failed, unconfirmed
}

public func canRemoveShelfCopy(receipt: DeliveryReceipt) -> Bool {
    receipt == .confirmed
}

/// Combines two independent observations for one drag. Cancellation and write failure
/// are terminal, including when a delayed promise callback arrives afterward.
public struct DeliveryGate: Sendable {
    public private(set) var receipt: DeliveryReceipt = .unconfirmed
    private var verifiedWrite = false
    private var acceptedCopy = false
    public init() {}
    @discardableResult public mutating func markWriteVerified() -> DeliveryReceipt {
        guard receipt == .unconfirmed else { return receipt }
        verifiedWrite = true
        if acceptedCopy { receipt = .confirmed }
        return receipt
    }
    @discardableResult public mutating func markWriteFailed() -> DeliveryReceipt {
        if receipt == .unconfirmed { receipt = .failed }
        return receipt
    }
    @discardableResult public mutating func end(acceptedCopy: Bool) -> DeliveryReceipt {
        guard receipt == .unconfirmed else { return receipt }
        guard acceptedCopy else { receipt = .cancelled; return receipt }
        self.acceptedCopy = true
        if verifiedWrite { receipt = .confirmed }
        return receipt
    }
}
