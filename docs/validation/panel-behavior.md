# Panel feasibility evidence

2026-10-25. Minimum deployment target: macOS 14. Built locally using Swift 6.4.

## Implemented probe

Run `scripts/build-app.sh --probe`, then `open .build/apps/IslandProbe.app --args panel`.
A controlled host window provides an editable text field and an explicit full-screen toggle.
Explicit launch activates that owned host. Hover presentation never calls app activation or makes the panel key.

The trigger is 180 points wide, horizontally centered, with menu-bar/safe-area height.
It uses pointer polling without an invisible trigger window or global event monitor.
The visible 680×180 panel uses `.nonactivatingPanel`, `.statusBar`, `.canJoinAllSpaces`, and `.fullScreenAuxiliary`.
The geometry uses AppKit global coordinates, including secondary display offsets, and clamps oversized content to the selected screen.
When hidden, the selected display follows the pointer; it stays fixed while visible.

`Enable typing deliberately` permits the panel to become key and selects its input field.
Pointer exit hides the panel in hover mode; explicit input mode stays open until `Done / dismiss`.
Text stays in the field across dismissal, never logged. Quit via the owned host's `Quit probe` button.
Host installation inventory is consumed read-only; no terminal session interaction occurs.

## Evidence boundaries

- Observed: build succeeds; geometry tests 3/3 and complete suite 8/8 pass.
- Observed: `open ... --args panel` returned status 0. This confirms launch dispatch only.
- Unverified: rendered host/panel appearance, hover discovery, focus preservation, typing, text preservation, pointer exit, menu bar access, Spaces switching, full-screen overlay, multiple physical displays.
- Configuration above is implementation evidence, not a successful full-screen/focus acceptance claim.
- No permission prompts were requested or approved. No unrelated app UI was manipulated.

## Live acceptance procedure (pending)

1. Type a harmless marker into the controlled host field; hover top center; continue typing. Verify host focus and text preservation.
2. Move the pointer outside the panel. Verify hover panel dismissal and menu bar access beyond the narrow trigger.
3. Reopen; select `Enable typing deliberately`, type harmless text; move outside; confirm editing remains open. Dismiss/reopen and confirm field text persists.
4. Use the host's full-screen toggle. Repeat hover/focus/input tests; use native Spaces switching and return. Confirm overlay targets the current display/Space.
5. Exit full screen and repeat. Record visual evidence and limitations separately, including actual OS/display configuration.

No full-screen acceptance promise is made before these live checks. Other-app full-screen compatibility remains separate from the controlled host result.

### Launch diagnostics

Own-process verification confirmed PID 29467 `isFinishedLaunching=true`, accessory activation policy. CoreGraphics own-window metadata reported a 640×332 titled host and 680×180 panel at layer 25. Sampling showed the normal AppKit run loop and pointer timer (not a blocked inventory call). A diagnostic duplicate direct launch was terminated; original probe left running for root checks. Root CUA resolves by bundle ID `dev.nativeisland.probe`; lookup by full bundle path timed out. Root reports actual AX/screenshot of visible hover-mode panel and controls; interaction/full-screen results pending separately.

## Phase 3 final evidence reconciliation — 2026-10-26

The dimensions and controls above describe the Phase 1 probe, not a verified rendering of the current app. Root observed early native Home and Settings and an English → Indonesian → English switch. The rendered navigation appeared as a row, rather than the intended footer placement; this minor appearance discrepancy remains deferred. Compact layout, scaling, Reduce Motion, keyboard focus indicators, hidden menu-bar click access, current-build hover and full-screen interaction remain unverified. No visual PASS is inferred from geometry or reducer tests.

Task 3 CUA inventory responded but did not list IslandMac; no app launch/restart or `--show` instance was used to force visibility. An older process may still exist outside that inventory and may still run the earlier binary. The pre-existing SwiftPM native-engine deprecation warning remains visible; the current CLT test workaround is documented in README. See mvp-acceptance.md for all 15 criteria and explicit implementation gaps.
