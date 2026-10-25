import Testing
@testable import IslandCore

struct DeliveryReceiptTests {
    @Test func writeBeforeCancelRetainsCopy() {
        var gate = DeliveryGate()
        #expect(gate.markWriteVerified() == .unconfirmed)
        #expect(gate.end(acceptedCopy: false) == .cancelled)
        #expect(gate.receipt == .cancelled)
    }

    @Test func cancelBeforeWriteRetainsCopy() {
        var gate = DeliveryGate()
        #expect(gate.end(acceptedCopy: false) == .cancelled)
        #expect(gate.markWriteVerified() == .cancelled)
    }

    @Test func acceptedBeforeWriteConfirms() {
        var gate = DeliveryGate()
        #expect(gate.end(acceptedCopy: true) == .unconfirmed)
        #expect(gate.markWriteVerified() == .confirmed)
    }

    @Test func writeBeforeAcceptedConfirms() {
        var gate = DeliveryGate()
        #expect(gate.markWriteVerified() == .unconfirmed)
        #expect(gate.end(acceptedCopy: true) == .confirmed)
    }

    @Test func failedWriteVetoesAcceptedOperation() {
        var gate = DeliveryGate()
        #expect(gate.end(acceptedCopy: true) == .unconfirmed)
        #expect(gate.markWriteFailed() == .failed)
        #expect(gate.markWriteVerified() == .failed)
    }
    @Test func confirmedTransferPermitsRemoval() { #expect(canRemoveShelfCopy(receipt: .confirmed)) }
    @Test func cancelledTransferRetainsCopy() { #expect(!canRemoveShelfCopy(receipt: .cancelled)) }
    @Test func failedTransferRetainsCopy() { #expect(!canRemoveShelfCopy(receipt: .failed)) }
    @Test func unconfirmedTransferRetainsCopy() { #expect(!canRemoveShelfCopy(receipt: .unconfirmed)) }
}
