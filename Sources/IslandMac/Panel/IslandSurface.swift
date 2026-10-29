import SwiftUI

@MainActor final class IslandSurfaceState: ObservableObject {
    @Published var size: CGSize?
    @Published var opacity: Double = 1
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
