import Foundation
import CoreGraphics
import Testing
@testable import IslandCore

struct PanelGeometryTests {
    @Test func centeredAtTop() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let trigger = PanelGeometry.triggerRect(screen: screen, menuBarHeight: 24)
        #expect(trigger.midX == 720)
        #expect(trigger.height == 24)
        #expect(trigger.maxY == 900)
        let panel = PanelGeometry.panelRect(screen: screen, size: CGSize(width: 680, height: 180))
        #expect(panel == CGRect(x: 380, y: 720, width: 680, height: 180))
    }
    @Test func secondaryScreenOriginIsPreserved() {
        let screen = CGRect(x: -1440, y: 250, width: 1440, height: 900)
        let panel = PanelGeometry.panelRect(screen: screen, size: CGSize(width: 680, height: 180))
        let trigger = PanelGeometry.triggerRect(screen: screen, menuBarHeight: 24)
        #expect(panel.midX == screen.midX)
        #expect(panel.maxY == screen.maxY)
        #expect(screen.contains(panel))
        #expect(screen.contains(trigger))
        #expect(trigger.maxY == screen.maxY)
    }
    @Test func smallScreenClampsBounds() {
        let screen = CGRect(x: 50, y: -300, width: 120, height: 100)
        #expect(PanelGeometry.panelRect(screen: screen, size: CGSize(width: 680, height: 180)) == screen)
        #expect(screen.contains(PanelGeometry.triggerRect(screen: screen, menuBarHeight: 200)))
    }
}
