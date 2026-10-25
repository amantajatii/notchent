import Foundation
import Testing
@testable import IslandCore

struct FileShelfTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.txt")
        try Data("fixture".utf8).write(to: source)
        return (root, source)
    }

    @Test func duplicateNamesAndCopySurvivesOriginalDeletion() async throws {
        let (root, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let second = root.appendingPathComponent("other/source.txt")
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: second)
        let shelf = try FileShelf(root: root.appendingPathComponent("Shelf"))
        let imported = try await shelf.importFiles([source, second], mode: .copy)
        #expect(imported.count == 2)
        #expect(imported[0].id != imported[1].id)
        #expect(imported[0].displayName == imported[1].displayName)
        try FileManager.default.removeItem(at: source)
        let reopened = try FileShelf(root: root.appendingPathComponent("Shelf"))
        let items = await reopened.items()
        #expect(items.count == 2)
        let allAvailable = items.allSatisfy { $0.isAvailable }
        #expect(allAvailable)
        #expect(try await reopened.url(for: imported[0].id) != nil)
    }

    @Test func missingReferenceIsUnavailableNotDeleted() async throws {
        let (root, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let shelf = try FileShelf(root: root.appendingPathComponent("Shelf"))
        let item = try await shelf.importFiles([source], mode: .reference).first!
        try FileManager.default.removeItem(at: source)
        let reopened = try FileShelf(root: root.appendingPathComponent("Shelf"))
        #expect(await reopened.items().first?.isAvailable == false)
        #expect(try await reopened.url(for: item.id) == nil)
    }

    @Test func removalLeavesOriginalUntouched() async throws {
        let (root, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let shelf = try FileShelf(root: root.appendingPathComponent("Shelf"))
        let item = try await shelf.importFiles([source], mode: .copy).first!
        try await shelf.remove(item.id)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(await shelf.items().isEmpty)
    }

    @Test func interruptedWriteKeepsPreviousManifest() async throws {
        let (root, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("Shelf")
        let shelf = try FileShelf(root: location)
        let item = try await shelf.importFiles([source], mode: .copy).first!
        try Data("interrupted".utf8).write(to: location.appendingPathComponent("manifest.json.tmp"))
        let reopened = try FileShelf(root: location)
        #expect(await reopened.items().map(\.id) == [item.id])
    }

    @Test func unconfirmedDeliveryRetainsOwnedCopy() async throws {
        let (root, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let shelf = try FileShelf(root: root.appendingPathComponent("Shelf"))
        let item = try await shelf.importFiles([source], mode: .copy).first!
        for receipt in [DeliveryReceipt.cancelled, .failed, .unconfirmed] {
            try await shelf.completeDelivery(item.id, receipt: receipt)
            #expect(await shelf.items().count == 1)
            #expect(try await shelf.url(for: item.id) != nil)
        }
        try await shelf.completeDelivery(item.id, receipt: .confirmed)
        #expect(await shelf.items().isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}
