import Foundation
import CoreGraphics

public enum PanelGeometry {
    /// AppKit global coordinates; the hover area does not intercept menu bar clicks.
    public static func triggerRect(screen: CGRect, menuBarHeight: CGFloat) -> CGRect {
        panelRect(screen: screen, size: CGSize(width: 600, height: menuBarHeight))
    }

    public static func containsPointer(_ point: CGPoint, trigger: CGRect, expandedPanel: CGRect?) -> Bool {
        trigger.contains(point) || (expandedPanel?.insetBy(dx: -16, dy: -12).contains(point) ?? false)
    }

    public static func panelRect(screen: CGRect, size: CGSize) -> CGRect {
        let width = min(max(0, size.width), screen.width)
        let height = min(max(0, size.height), screen.height)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }

    public static func transitionRect(screen: CGRect, from: CGSize, to: CGSize, progress: Double) -> CGRect {
        let fraction = CGFloat(min(1, max(0, progress)))
        return panelRect(screen: screen, size: CGSize(width: from.width + (to.width - from.width) * fraction,
                                                     height: from.height + (to.height - from.height) * fraction))
    }

    public static func transitionViewport(screen: CGRect, from: CGSize, to: CGSize) -> CGRect {
        panelRect(screen: screen, size: CGSize(width: max(from.width, to.width), height: max(from.height, to.height)))
    }
}
