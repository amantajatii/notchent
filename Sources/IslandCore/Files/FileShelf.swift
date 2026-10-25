import Foundation

struct FileShelfOperations: Sendable {
    let copy: @Sendable (URL, URL) throws -> Void
    let writeManifest: @Sendable (Data, URL) throws -> Void
    static let live = Self(
        copy: { try FileManager.default.copyItem(at: $0, to: $1) },
        writeManifest: { try $0.write(to: $1, options: .atomic) }
    )
}

public struct ShelfItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let displayName: String
    public let storageMode: FileStorageMode
    public let ownedRelativePath: String?
    public let bookmark: Data?
    public var isAvailable: Bool

    public init(id: UUID, displayName: String, storageMode: FileStorageMode, ownedRelativePath: String?, bookmark: Data?, isAvailable: Bool) {
        self.id = id; self.displayName = displayName; self.storageMode = storageMode
        self.ownedRelativePath = ownedRelativePath; self.bookmark = bookmark; self.isAvailable = isAvailable
    }
}

public actor FileShelf {
    private let root: URL
    private let manifest: URL
    private var stored: [ShelfItem]
    private let operations: FileShelfOperations
    private let files = FileManager.default

    public init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IslandMac/FileShelf", isDirectory: true)) throws {
        try self.init(root: root, operations: .live)
    }

    init(root: URL, operations: FileShelfOperations) throws {
        self.root = root
        manifest = root.appendingPathComponent("manifest.json")
        self.operations = operations
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: manifest.path) {
            stored = try JSONDecoder().decode([ShelfItem].self, from: Data(contentsOf: manifest))
        } else { stored = [] }
    }

    public func items() -> [ShelfItem] {
        stored.map { item in
            var current = item
            current.isAvailable = resolvedURL(for: item) != nil
            return current
        }
    }

    public func url(for id: UUID) throws -> URL? {
        guard let item = stored.first(where: { $0.id == id }) else { return nil }
        return resolvedURL(for: item)
    }

    public func importFiles(_ urls: [URL], mode: FileStorageMode) async throws -> [ShelfItem] {
        var added: [ShelfItem] = []
        var owned: [URL] = []
        do {
            for source in urls {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let id = UUID()
                if mode == .copy {
                    let relative = "Files/\(id.uuidString)"
                    let target = root.appendingPathComponent(relative)
                    try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try validatedOwnedURL(for: ShelfItem(id: id, displayName: source.lastPathComponent, storageMode: .copy, ownedRelativePath: relative, bookmark: nil, isAvailable: true))
                    owned.append(target)
                    try operations.copy(source, target)
                    added.append(ShelfItem(id: id, displayName: source.lastPathComponent, storageMode: .copy, ownedRelativePath: relative, bookmark: nil, isAvailable: true))
                } else {
                    let bookmark = try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    added.append(ShelfItem(id: id, displayName: source.lastPathComponent, storageMode: .reference, ownedRelativePath: nil, bookmark: bookmark, isAvailable: true))
                }
            }
            try save(stored + added)
            stored += added
            return added
        } catch {
            for target in owned { try? files.removeItem(at: target) }
            throw error
        }
    }

    public func remove(_ id: UUID) async throws {
        guard let item = stored.first(where: { $0.id == id }) else { return }
        let ownedURL = item.storageMode == .copy ? try validatedOwnedURL(for: item) : nil
        let next = stored.filter { $0.id != id }
        try save(next)
        stored = next
        if let ownedURL { try? files.removeItem(at: ownedURL) }
    }

    public func completeDelivery(_ id: UUID, receipt: DeliveryReceipt) async throws {
        guard canRemoveShelfCopy(receipt: receipt) else { return }
        try await remove(id)
    }

    private func save(_ items: [ShelfItem]) throws {
        try operations.writeManifest(JSONEncoder().encode(items), manifest)
    }

    private func validatedOwnedURL(for item: ShelfItem) throws -> URL {
        guard let relative = item.ownedRelativePath,
              relative == "Files/\(item.id.uuidString)" else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = root.appendingPathComponent("Files", isDirectory: true)
        let target = directory.appendingPathComponent(item.id.uuidString)
        guard target.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL else { throw CocoaError(.fileReadInvalidFileName) }
        for url in [root, directory, target] where files.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
        }
        return target
    }

    private func resolvedURL(for item: ShelfItem) -> URL? {
        let url: URL
        if item.storageMode == .copy {
            guard let owned = try? validatedOwnedURL(for: item) else { return nil }
            url = owned
        } else {
            guard let bookmark = item.bookmark else { return nil }
            var stale = false
            guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale), !stale else { return nil }
            url = resolved
        }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }
}
