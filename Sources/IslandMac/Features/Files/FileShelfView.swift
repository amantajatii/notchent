import AppKit
import QuickLookThumbnailing
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if access.items.isEmpty {
                IslandEmptyState(title: shell.text("shelfEmpty"), symbol: "tray", message: shell.text("drop"))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(access.items) { item in FileTile(shell: shell, access: access, item: item) }
                    }
                }.frame(width: IslandDesign.contentWidth)
            }
            if let error = access.error { Text(error).font(IslandDesign.caption).foregroundStyle(IslandDesign.danger) }
        }.frame(width: IslandDesign.contentWidth, alignment: .leading)
    }
}

private struct FileTile: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    let item: ShelfItem
    private var isSelected: Bool { access.selected == item.id }

    var body: some View {
        VStack(spacing: 6) {
            FileThumbnail(item: item, access: access)
                .frame(width: 64, height: 58)
                .overlay(FileDragSource(item: item, access: access, dragEnded: { shell.dispatch?(.shelfDragEnded) }) { access.selected = item.id })
            Text(item.displayName).font(IslandDesign.caption).lineLimit(1).truncationMode(.middle)
                .help(item.displayName)
            if !item.isAvailable {
                Text(shell.text("shelfUnavailable")).font(IslandDesign.footnote).foregroundStyle(.orange)
            }
            if isSelected {
                Button(shell.text("shelfRemove")) { access.remove(item.id); access.selected = nil }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .tinted, tint: IslandDesign.danger)).controlSize(.small)
            }
        }
        .frame(width: 96)
        .padding(8)
        .background(isSelected ? IslandTint.files.opacity(0.18) : IslandDesign.card,
                    in: RoundedRectangle(cornerRadius: IslandDesign.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IslandDesign.rowRadius, style: .continuous)
            .strokeBorder(isSelected ? IslandTint.files : Color.clear, lineWidth: 1.5))
    }
}

struct FileShelfSummary: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    var body: some View {
        HStack(spacing: 10) {
            IslandGlyph(symbol: "tray.fill", tint: IslandTint.neutral, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(shell.text("files")).font(IslandDesign.title).foregroundStyle(IslandDesign.primary)
                Text("\(access.items.count) \(shell.text("shelfItems"))")
                    .font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary).lineLimit(1)
                if let error = access.error {
                    Text(error).font(IslandDesign.caption).foregroundStyle(IslandDesign.danger).lineLimit(2).help(error)
                }
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
