/// A confirmed receipt requires acknowledgement beyond native drag acceptance.
public enum DeliveryReceipt: String, Codable, Sendable {
    case confirmed, cancelled, failed, unconfirmed
}

public func canRemoveShelfCopy(receipt: DeliveryReceipt) -> Bool {
    receipt == .confirmed
}
