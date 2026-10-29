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
        #expect(trigger.width == 600)
        #expect(trigger.maxY == 900)
        let panel = PanelGeometry.panelRect(screen: screen, size: CGSize(width: 680, height: 180))
        #expect(panel == CGRect(x: 380, y: 720, width: 680, height: 180))
    }
    @Test func pointerCanReachPanelWithoutLosingHoverAtItsEdges() {
        let trigger = PanelGeometry.triggerRect(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), menuBarHeight: 24)
        let panel = CGRect(x: 420, y: 700, width: 600, height: 200)
        #expect(PanelGeometry.containsPointer(CGPoint(x: 440, y: 890), trigger: trigger, expandedPanel: nil))
        #expect(PanelGeometry.containsPointer(CGPoint(x: 410, y: 710), trigger: trigger, expandedPanel: panel))
        #expect(!PanelGeometry.containsPointer(CGPoint(x: 390, y: 710), trigger: trigger, expandedPanel: panel))
        #expect(!PanelGeometry.containsPointer(CGPoint(x: 410, y: 710), trigger: trigger, expandedPanel: nil))
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
    @Test func resizeAndCloseKeepTopAndCenterFixedAtEveryFrame() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1440, y: 250, width: 1440, height: 900)] {
            for (from, to) in [(CGSize(width: 700, height: 540), CGSize(width: 560, height: 160)), (CGSize(width: 560, height: 160), CGSize(width: 160, height: 26))] {
                for sample in 0...120 {
                    let frame = PanelGeometry.transitionRect(screen: screen, from: from, to: to, progress: Double(sample) / 120)
                    #expect(abs(frame.maxY - screen.maxY) < 0.0001)
                    #expect(abs(frame.midX - screen.midX) < 0.0001)
                    #expect(screen.contains(frame))
                    let viewport = PanelGeometry.transitionViewport(screen: screen, from: from, to: to)
                    #expect(viewport.contains(frame))
                    #expect(viewport.maxY == screen.maxY)
                }
                #expect(PanelGeometry.transitionRect(screen: screen, from: from, to: to, progress: 1) == PanelGeometry.panelRect(screen: screen, size: to))
            }
        }
    }
    @Test func retargetingDoesNotMoveTheVisibleSurface() {
        let screen = CGRect(x: -1440, y: 250, width: 1440, height: 900)
        let current = PanelGeometry.transitionRect(screen: screen, from: CGSize(width: 700, height: 540), to: CGSize(width: 560, height: 160), progress: 0.4)
        let newTarget = CGSize(width: 600, height: 240)
        let viewport = PanelGeometry.transitionViewport(screen: screen, from: current.size, to: newTarget)
        #expect(viewport.contains(current))
        #expect(PanelGeometry.transitionRect(screen: screen, from: current.size, to: newTarget, progress: 0) == current)
    }
    @Test func smallScreenClampsBounds() {
        let screen = CGRect(x: 50, y: -300, width: 120, height: 100)
        #expect(PanelGeometry.panelRect(screen: screen, size: CGSize(width: 680, height: 180)) == screen)
        #expect(screen.contains(PanelGeometry.triggerRect(screen: screen, menuBarHeight: 200)))
    }
}
