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

## Current native app interaction and visual revision — 2026-10-26

The current app uses a 600-point centered trigger at menu-bar height. While expanded, a 16-point horizontal / 12-point vertical margin retains hover. The panel follows the pointer's display when hidden and stays on that display while open. Pointer sampling runs at 60 Hz in common run-loop modes. These replace the probe's narrow target and the app's former built-in-display selection.

Opening expands from a small top-centered capsule over 340 ms; closing contracts over 200 ms. Content stays mounted until close completes. A generation check rejects obsolete close completions, and pointer re-entry during contraction reopens immediately. Content-size preferences resize the panel after SwiftUI layout changes. Reduce Motion uses a short fade without spatial expansion. Home/music/navigation/settings/empty states are compact and use localized application labels.

Verification: four geometry tests and nine existing reducer/regression tests passed; the native app builds and packages. These checks do not prove animation smoothness or final visual quality. CUA app inspection timed out, so this revision has not been visually inspected or used to replace the user's running app. The old process remains alive; a normal Quit/reopen is required. Saved delays were observed as open 0 ms / close 300 ms and were preserved.

## Top-locked motion and surface refinement — 2026-10-26

Reported defect: when moving to shorter content, a fixed-size SwiftUI root was centered inside the still-tall window, leaving a temporary transparent gap above the island. IslandSurface now fills the entire animated viewport and pins natural-sized content to the top. Inner content measurements include both mode and size, so equal-size route changes still refresh ownership. A small initial mount handles uncached content and the first pending-only indicator. Measurements from obsolete modes are ignored.

Window resizing now uses the screen's native CADisplayLink. Every frame interpolates size and derives the origin from the display's top and horizontal center; it does not independently animate y. Open/resize decelerate over 360/280 ms, close contracts over 200 ms, interruption starts at the actual current size/opacity, and old display links are invalidated. Reduce Motion snaps geometry and uses a brief fade. The display link stops when the transition ends. The navigation has fixed labeled slots, and the prompt header replaces its redundant pending banner; its primary one-time action has a stronger fill without decorative outlines.

Synchronous Spotify metadata/control IPC now runs on a serial worker actor. The immutable event client is compiler-checked Sendable; NSRunningApplication is documented thread-safe and Sendable in the SDK. Fresh PID/launch-date checks and permission preflight remain around every send, and interactive consent stays on MainActor. Snapshot cancellation is checked before reads. No playback or consent was changed for validation.

Verification: 23 focused tests passed (Spotify opt-in read skipped), including native ImageRenderer pixel checks across shrinking viewport heights, 120-frame top/center geometry samples for primary/offset displays, equal-size mode measurements, hover reducers, identity checks and stale Spotify polling. Two actual Home component renders with bundled English/Indonesian resources were visually inspected in one capture pass plus one localization-harness correction pass. These use initial service state, not live music/agent data. A hidden NSHostingView callback experiment did not initialize a render lifecycle in the bare test runner; it was not counted as a native window pass. Scoped code review approved the layout, interrupted-close/indicator bootstrap and Spotify actor changes. Live AppKit frame pacing, host callbacks, interactive navigation and pointer behavior remain unverified because CUA window inspection timed out. A normal app Quit/reopen is required to load this build.

## Startup and reopen repair — 2026-10-27

The first SwiftUI size preference could be overwritten by a zero-size default contribution, leaving the startup surface tiny and nearly transparent. Invalid measurements are now ignored; uncached content mounts in a readable top-attached viewport. Normal launch, menu Open and application reopen explicitly reveal Home for at least five seconds, after which normal hover dismissal resumes. Pointer entry cancels that temporary dismissal; leaving uses the saved close delay.

Verification: 16 focused tests passed, covering measurement reduction, reveal timeout, pointer re-entry and preserved longer user delays. The packaged app built and passed strict code-signature verification. A controlled duplicate showed Home and Music through native UI automation, then was closed. The previous production instance was normally quit, and the repaired production bundle was opened without --show. Its Home, live Spotify metadata and transport controls were visibly present. Hide followed by opening the already-running bundle restored the panel. No playback, agent answer or permission grant was performed. Live frame pacing, full-screen behavior and multi-display hover remain unverified.

## Unified content and close motion — 2026-10-27

Content now composites as one top-anchored group and scales uniformly with narrower surface widths. Navigation no longer has an independent implicit route animation. Closing uses a smooth acceleration/deceleration curve, fades content in the first 45 percent, and retains the black silhouette until its last 35 percent. Interrupted motion resumes from the current content opacity. The opening geometry curve is unchanged; Reduce Motion still snaps geometry and fades.

Five surface tests passed; the optional capture test was skipped. A new pixel regression checks both halves of a shrinking group and confirms that fading content retains an opaque black backplate. This is component-render evidence, not a live smoothness assessment.

## Natural-size content and matching open/close — 2026-10-27

Follow-up feedback rejected the content zoom and the separately staged exit. Removed the content scale and separate content-opacity timeline. Content remains composited at its natural fixed size, with independent navigation animation still disabled. Both open and close now run for 320 ms with the same quartic ease-out geometry and cubic ease-out opacity interpolation, toward opposite targets. Route resize remains 260 ms. Reduce Motion keeps its existing 100 ms fade. This supersedes the unified-content section's scaling and staged-fade behavior.

A pixel regression checks that both halves of grouped content retain their natural height and center through three viewport widths, detecting the removed zoom behavior. Live animation quality still requires user assessment.

## Slower motion and sliding tab marker — 2026-10-27

Opening and closing now share a 480 ms duration; route resizing uses 400 ms. Existing top anchoring, display-link interpolation and interrupted-motion handling remain. The navigation uses one 74-point highlight behind the fixed tab labels, sliding between 78-point slot centers over 420 ms; only that highlight animates, not the labels or their layout. Reduce Motion retains the 100 ms surface fade and snaps the tab marker. The packaged build and strict signature check passed. Native UI inspection confirmed the updated compact Agents list is loaded; continuous frame pacing and the perceived smoothness of the tab marker have not been measured.

## Global file-drag activation — 2026-10-27

The panel now opens its drop area as soon as a held mouse button accompanies a fresh file-URL drag pasteboard, regardless of cursor position. Mouse-up/cancel clears activation; stale file pasteboard data and text drags cannot trigger it. Leaving the panel while still dragging no longer dismisses the drop area. Successful drop consumes the pasteboard generation before dismissal to prevent immediate reopening. Actual imports remain gated by the visible silhouette. Mission Control configuration is unchanged; users can target the already-open drop area below the screen edge. Two activation regressions passed as part of the full suite; Finder dragging from the lower screen has not yet been verified live.
