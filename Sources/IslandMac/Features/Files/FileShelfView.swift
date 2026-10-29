import AppKit
import QuickLookThumbnailing
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if access.items.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "tray").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(shell.text("shelfEmpty")).font(.system(size: 15, weight: .medium))
                        Text(shell.text("drop")).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(width: 520, height: 76, alignment: .leading)
            }
            else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(access.items) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                FileThumbnail(item: item, access: access)
                                    .frame(width: 64, height: 58)
                                    .overlay(FileDragSource(item: item, access: access, dragEnded: { shell.dispatch?(.shelfDragEnded) }) { access.selected = item.id })
                                Text(item.displayName).font(.caption2).lineLimit(1).truncationMode(.middle)
                                    .help(item.displayName)
                                if !item.isAvailable { Text(shell.text("shelfUnavailable")).font(.caption2).foregroundStyle(.orange) }
                                if access.selected == item.id {
                                    Button(shell.text("shelfRemove")) { access.remove(item.id); access.selected = nil }
                                        .font(.caption2)
                                }
                            }
                            .frame(width: 96, alignment: .leading)
                            .padding(7)
                            .background(access.selected == item.id ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }.frame(width: 520)
            }
            if let error = access.error { Text(error).font(.caption2).foregroundStyle(.red) }
        }.frame(width: 520, alignment: .leading)
    }
}

struct FileShelfSummary: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(shell.text("files"), systemImage: "square.stack")
            Text("\(access.items.count) \(shell.text("shelfItems"))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if let error = access.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2).help(error)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

private struct FileThumbnail: View {
    let item: ShelfItem
    @ObservedObject var access: NativeFileAccess
    @StateObject private var thumbnail = ThumbnailModel()
    var body: some View {
        Image(nsImage: thumbnail.image ?? NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.displayName as NSString).pathExtension) ?? .data))
            .resizable().scaledToFit().opacity(item.isAvailable ? 1 : 0.4)
            .task(id: item.id) {
                guard let url = await access.sourceURL(for: item.id) else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 128, height: 128), scale: 2, representationTypes: [.thumbnail, .icon])
                thumbnail.image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
    }
}

@MainActor private final class ThumbnailModel: ObservableObject { @Published var image: NSImage? }
