import AppKit
import IslandCore

@MainActor final class NativeFileAccess: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var selected: UUID?
    @Published var error: String?
    private let shelf: FileShelf?

    init() {
        do { shelf = try FileShelf() }
        catch { shelf = nil; self.error = error.localizedDescription }
        refresh()
    }

    func refresh() {
        guard let shelf else { return }
        Task { items = await shelf.items() }
    }

    func importURLs(_ urls: [URL], mode: FileStorageMode) {
        guard let shelf else { return }
        Task {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            do { _ = try await shelf.importFiles(urls, mode: mode); error = nil; items = await shelf.items() }
            catch { self.error = error.localizedDescription }
        }
    }

    func remove(_ id: UUID) {
        guard let shelf else { return }
        Task {
            do { try await shelf.remove(id); error = nil; items = await shelf.items() }
            catch { self.error = error.localizedDescription }
        }
    }

    func sourceURL(for id: UUID) async -> URL? { try? await shelf?.url(for: id) }

    func finishDelivery(_ id: UUID, receipt: DeliveryReceipt) {
        guard let shelf else { return }
        Task {
            do { try await shelf.completeDelivery(id, receipt: receipt); items = await shelf.items() }
            catch { self.error = error.localizedDescription }
        }
    }

    /// A producer-controlled promise is confirmed only after this app wrote the destination
    /// and independently compared its bytes with the retained source. No source is removed here.
    func writePromise(for id: UUID, to destination: URL) async throws {
        guard let source = await sourceURL(for: id) else { throw CocoaError(.fileReadNoSuchFile) }
        try await Task.detached(priority: .userInitiated) {
            try Self.copyAndVerify(source: source, destination: destination)
        }.value
    }

    private nonisolated static func copyAndVerify(source: URL, destination: URL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            let left = try FileHandle(forReadingFrom: source)
            let right = try FileHandle(forReadingFrom: destination)
            defer { try? left.close(); try? right.close() }
            while true {
                let a = try left.read(upToCount: 256 * 1024) ?? Data()
                let b = try right.read(upToCount: 256 * 1024) ?? Data()
                guard a == b else { throw CocoaError(.fileWriteUnknown) }
                if a.isEmpty { break }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
