# Task 2 implementation report

Status: DONE_WITH_CONCERNS — implementation and geometry verification complete; live GUI acceptance pending root CUA checks.

## Changes and service interfaces

- `Sources/IslandCore/Presentation/PanelGeometry.swift`: public static `triggerRect(screen: CGRect, menuBarHeight: CGFloat) -> CGRect`, `panelRect(screen: CGRect, size: CGSize) -> CGRect`. Global AppKit coordinate geometry, horizontal center/top alignment, clamp oversized panels.
- `Sources/IslandProbe/PanelProbe.swift`: real nonactivating NSPanel with explicit deliberate key/input mode, pointer-only hover target, dismissal with retained text, read-only host inventory consumption, owned host full-screen toggle.
- `Sources/IslandProbe/main.swift`: dispatch `panel` to `PanelProbe.run()`; other scenarios unchanged.
- `Tests/IslandCoreTests/PanelGeometryTests.swift`: exact 1440×900 / 24-point / 680×180 bounds, secondary origin (-1440,250), oversized content.
- `docs/validation/panel-behavior.md`: reproducible procedure and truthful pending live checks.

Assumption: brief leaves trigger width unspecified; use narrow 180pt width. Hover opens immediately and polls pointer every 50ms. Production configurable delays are outside this probe.

## TDD evidence

RED: `scripts/test.sh --filter PanelGeometryTests`, before geometry implementation, failed with `cannot find 'PanelGeometry' in scope`. Package/test harness already existed; failure was missing required implementation.

GREEN: same command after implementation passed 3 tests in 1 suite. `scripts/test.sh` passed 8 tests in 2 suites. `scripts/build-app.sh --probe` succeeded. Toolchain emits pre-existing native build-system deprecation warning; no compiler warnings/errors remain.

A first implementation compile required explicit `CoreGraphics` import for CGRect Swift overlay members; fixed before GREEN.

## GUI evidence and concerns

Ran `open .build/apps/IslandProbe.app --args panel`, exit 0. Root notified of ready owned host and controls. No rendered/focus/full-screen claim follows from launch success. Full live matrix is unverified until CUA observations are appended. No unrelated apps or permission grants were manipulated.

Initial explicit launch intentionally activates the owned host to make it accessible for testing. Hover path never activates the app; NSPanel remains non-key until explicit button action. Actual behavior must be observed. Full-screen targeting has not been declared accepted.

Self-review: limited pointer interception to the visible panel; no screen-sized invisible windows, no terminal/text/environment logging. Geometry tests use actual CoreGraphics types and offsets. Input mode deliberately ignores pointer exit so editing is not interrupted. Selected display stays fixed while visible. No task-1 identity interfaces changed.

Launch follow-up: full-path CUA lookup timed out, but root successfully resolved bundle ID `dev.nativeisland.probe` and observed the panel/controls by AX and screenshot. Own NSWorkspace confirmed finished launch; own-window CoreGraphics metadata confirmed host and 680×180 layer25 panel. Sample of own process showed normal AppKit run loop and timer, disproving a tentative inventory-block hypothesis; no speculative code change made. Diagnostic duplicate terminated; original probe retained for root interaction checks. Full-screen/focus acceptance still pending.
