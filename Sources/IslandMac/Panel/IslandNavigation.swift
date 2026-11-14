import SwiftUI
import IslandCore

/// Where the navigation row sits in the hosting view, so the panel controller can test the pointer.
struct NavigationFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// Centred page dots that turn into icons while the pointer is over the top row.
/// Hover comes from the controller's pointer polling, not SwiftUI's `onHover`: when a terminal takes
/// focus AppKit replays exit/enter on its tracking areas, which made every icon collapse and bloom again.
struct IslandNavigation: View {
    static let tabs: [IslandFeature] = [.home, .agents, .music, .files, .terminal]

    let selected: IslandFeature
    let title: (IslandFeature) -> String
    let select: (IslandFeature) -> Void
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: hovering ? Metrics.iconSpacing : Metrics.dotSpacing) {
            ForEach(Array(Self.tabs.enumerated()), id: \.element) { index, feature in
                NavigationItem(symbol: Self.symbol(for: feature), title: title(feature),
                               selected: feature == selected, expanded: hovering) { select(feature) }
                    .animation(itemAnimation(index), value: hovering)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: hovering)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: selected)
        .frame(width: IslandDesign.contentWidth, height: Metrics.rowHeight)
        .contentShape(Rectangle())
        .background(GeometryReader { Color.clear.preference(key: NavigationFrameKey.self, value: $0.frame(in: .global)) })
    }

    /// Icons bloom left to right; collapsing back to dots happens together.
    private func itemAnimation(_ index: Int) -> Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.12) }
        let base = Animation.spring(response: 0.32, dampingFraction: 0.82)
        return hovering ? base.delay(Double(index) * 0.025) : base
    }

    static func symbol(for feature: IslandFeature) -> String {
        switch feature {
        case .home: "square.grid.2x2"
        case .agents: "square.3.layers.3d"
        case .music: "music.note"
        case .files: "tray"
        case .terminal: "terminal"
        }
    }

    fileprivate enum Metrics {
        static let rowHeight: CGFloat = 28
        static let iconSlot: CGFloat = 30
        static let dotSlot: CGFloat = 12
        static let iconSpacing: CGFloat = 6
        static let dotSpacing: CGFloat = 2
        static let dot: CGFloat = 5
        static let selectedDotWidth: CGFloat = 14
    }
}

private struct NavigationItem: View {
    let symbol: String
    let title: String
    let selected: Bool
    let expanded: Bool
    let action: () -> Void
    private typealias Metrics = IslandNavigation.Metrics

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(selected ? IslandDesign.fillStrong : .clear)
                    .frame(width: Metrics.iconSlot - 2, height: Metrics.iconSlot - 2)
                    .scaleEffect(expanded ? 1 : 0.4)
                    .opacity(expanded ? 1 : 0)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? IslandDesign.primary : IslandDesign.secondary)
                    .scaleEffect(expanded ? 1 : 0.3)
                    .blur(radius: expanded ? 0 : 3)
                    .opacity(expanded ? 1 : 0)
                Capsule()
                    .fill(selected ? IslandDesign.primary : IslandDesign.tertiary)
                    .frame(width: selected ? Metrics.selectedDotWidth : Metrics.dot, height: Metrics.dot)
                    .scaleEffect(expanded ? 0.2 : 1)
                    .opacity(expanded ? 0 : 1)
            }
            .frame(width: expanded ? Metrics.iconSlot : (selected ? Metrics.selectedDotWidth + 4 : Metrics.dotSlot),
                   height: Metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The selected circle already marks the page; the square focus ring would fight it.
        .focusEffectDisabled()
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
