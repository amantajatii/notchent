import SwiftUI
import IslandCore

@MainActor final class IslandSurfaceState: ObservableObject {
    @Published var size: CGSize?
    @Published var opacity: Double = 1
    @Published var reveal = ContentReveal()
}

/// A tiny observable box: this toolchain has no SwiftUI macro plugin, so `@State` is unavailable.
@MainActor final class ViewFlag<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// How the island's content enters after the shape has moved (and leaves before it collapses).
struct ContentReveal: Equatable {
    var id = 0
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var delay: Double = 0
    var hiding = false
    var isPageSwitch: Bool { dx != 0 }

    /// Tabs slide in from the side they sit on; opening from the pill drops in after the shape grows.
    static func between(_ old: IslandMode, _ new: IslandMode, after previous: ContentReveal) -> ContentReveal {
        var next = ContentReveal(id: previous.id &+ 1)
        if let from = tabIndex(old), let to = tabIndex(new) {
            next.dx = to > from ? 14 : (to < from ? -14 : 0)
        } else if new != .mini && new != .hidden {
            next.dy = -6
            next.delay = (old == .mini || old == .hidden) ? 0.08 : 0
        }
        return next
    }

    private static func tabIndex(_ mode: IslandMode) -> Int? {
        switch mode {
        case .home: 0
        case let .feature(feature): IslandNavigation.tabs.firstIndex(of: feature)
        default: nil
        }
    }
}

/// A screen attachment with small inward shoulders and rounded lower corners.
struct IslandSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder = min(8, rect.width / 8, rect.height / 3)
        let radius = min(24, (rect.width - 2 * shoulder) / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder), control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.maxY), control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - radius), control: CGPoint(x: rect.minX + shoulder, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Only this surface changes size; the hosting viewport stays still during motion.
struct IslandSurface<Content: View>: View {
    @ObservedObject var state: IslandSurfaceState
    let content: Content
    init(state: IslandSurfaceState = IslandSurfaceState(), @ViewBuilder content: () -> Content) {
        self.state = state; self.content = content()
    }
    var body: some View {
        content
            .modifier(ContentRevealEffect(reveal: state.reveal, level: .island))
            .compositingGroup()
            .transaction { $0.animation = nil }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .frame(width: state.size?.width, height: state.size?.height, alignment: .top)
            .background(.black)
            .clipShape(IslandSilhouette())
            .contentShape(IslandSilhouette())
            .opacity(state.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Wraps only the page below the navigation, so switching tabs moves the page and never the menu.
struct PageReveal<Content: View>: View {
    @ObservedObject var state: IslandSurfaceState
    @ViewBuilder var content: Content
    var body: some View { content.modifier(ContentRevealEffect(reveal: state.reveal, level: .page)) }
}

/// Content fades in from a light blur and a small offset; the shape has already started moving.
struct ContentRevealEffect: ViewModifier {
    /// `.island` plays when the island opens, changes mode, or closes; `.page` plays only on tab switches.
    enum Level { case island, page }
    let reveal: ContentReveal
    let level: Level
    @StateObject private var applied = ViewFlag<Int?>(nil)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var applies: Bool {
        switch level {
        case .island: !reveal.isPageSwitch || reveal.hiding
        case .page: reveal.isPageSwitch && !reveal.hiding
        }
    }

    func body(content: Content) -> some View {
        // A new id renders hidden in the same pass, so new content never flashes at full strength.
        let shown = !applies || (applied.value == reveal.id && !reveal.hiding)
        let still = reduceMotion
        content
            // Switching tabs starts from a faint ghost rather than an empty frame.
            .opacity(shown ? 1 : (reveal.isPageSwitch ? 0.25 : 0))
            .blur(radius: shown || still ? 0 : 8)
            .offset(x: shown || still ? 0 : reveal.dx, y: shown || still ? 0 : reveal.dy)
            .animation(animation(shown: shown), value: shown)
            .task(id: reveal.id) { applied.value = reveal.id }
    }

    private func animation(shown: Bool) -> Animation? {
        if shown { return .easeOut(duration: reduceMotion ? 0.12 : 0.26).delay(reveal.delay) }
        return reveal.hiding ? .easeIn(duration: 0.12) : nil
    }
}
