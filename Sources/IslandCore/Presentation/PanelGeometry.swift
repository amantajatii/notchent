import Foundation
import CoreGraphics

public enum PanelGeometry {
    /// AppKit global coordinates; a narrow pointer target, not an intercepting window.
    public static func triggerRect(screen: CGRect, menuBarHeight: CGFloat) -> CGRect {
        panelRect(screen: screen, size: CGSize(width: 180, height: menuBarHeight))
    }

    public static func panelRect(screen: CGRect, size: CGSize) -> CGRect {
        let width = min(max(0, size.width), screen.width)
        let height = min(max(0, size.height), screen.height)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
}
