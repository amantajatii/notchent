import Testing
@testable import IslandCore

struct DeliveryReceiptTests {
    @Test func confirmedTransferPermitsRemoval() { #expect(canRemoveShelfCopy(receipt: .confirmed)) }
    @Test func cancelledTransferRetainsCopy() { #expect(!canRemoveShelfCopy(receipt: .cancelled)) }
    @Test func failedTransferRetainsCopy() { #expect(!canRemoveShelfCopy(receipt: .failed)) }
    @Test func unconfirmedTransferRetainsCopy() { #expect(!canRemoveShelfCopy(receipt: .unconfirmed)) }
}
