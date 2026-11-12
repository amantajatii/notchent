import AppKit
import QuickLookThumbnailing
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    private static let maximumListHeight: CGFloat = 232

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if access.items.isEmpty {
                IslandEmptyState(title: shell.text("shelfEmpty"), symbol: "tray", message: shell.text("drop"), tint: IslandTint.files)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(shell.text("files")).islandLabel()
                    Text("\(access.items.count)").islandHero().contentTransition(.numericText())
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(access.items) { item in FileRow(shell: shell, access: access, item: item) }
                    }
                }.frame(maxHeight: Self.maximumListHeight)
            }
            if let error = access.error { Text(error).font(IslandDesign.caption).foregroundStyle(IslandDesign.danger) }
        }
        .padding(.horizontal, 4)
        .frame(width: IslandDesign.contentWidth, alignment: .leading)
        .animation(IslandDesign.spring, value: access.items.count)
    }
}

private struct FileRow: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var access: NativeFileAccess
    let item: ShelfItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isSelected: Bool { access.selected == item.id }

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(item: item, access: access)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(IslandDesign.body).lineLimit(1).truncationMode(.middle)
                    .help(item.displayName)
                if !item.isAvailable {
                    Text(shell.text("shelfUnavailable")).font(IslandDesign.caption).foregroundStyle(IslandDesign.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(FileDragSource(item: item, access: access, dragEnded: { shell.dispatch?(.shelfDragEnded) }) { access.selected = item.id })
            trailing
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isSelected ? IslandDesign.fill : Color.clear,
                    in: RoundedRectangle(cornerRadius: IslandDesign.rowRadius, style: .continuous))
        .animation(reduceMotion ? nil : IslandDesign.spring, value: isSelected)
    }

    @ViewBuilder private var trailing: some View {
        if isSelected {
            Button(shell.text("shelfRemove")) { access.remove(item.id); access.selected = nil }
                .buttonStyle(IslandPillButtonStyle(emphasis: .destructive, tint: IslandDesign.danger))
        } else {
            Text(shell.text(item.storageMode == .copy ? "copy" : "reference"))
                .font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary)
        }
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
