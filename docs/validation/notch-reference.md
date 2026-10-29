# Notch reference adaptation — 2026-10-27

Inspected [spitfiresb/notch](https://github.com/spitfiresb/notch/tree/c86c0b8939b184133189014d87d2fe3431822b48), commit `c86c0b8939b184133189014d87d2fe3431822b48`. Upstream was cloned to a temporary read-only study directory; its scripts/app were not run. No explicit reuse license was found in the inspected tree. The local changes independently implement general interaction/layout ideas; no upstream source files or artwork were vendored.

## Applied patterns

- Stable viewport: the physical panel is sized to contain the current and destination visual sizes. It remains fixed during a transition; a dedicated observable surface interpolates its size/opacity inside it. The physical window compacts at rest. This avoids resizing the hosting window on every animation tick.
- Top attachment: the visual surface is top-centered, has small inward shoulders and rounded lower corners. AppKit frame constraints cannot push this controlled overlay below the menu bar. Every visual frame keeps the screen's top/center anchor.
- Input footprint: mouse events pass through clear viewport areas. The same actual silhouette/opacity predicate gates native drag entry/update/drop; transparent padding does not count as an accepted file drop.
- Timing: 320 ms open, 260 ms route resize, 220 ms close; interruption starts from current visual size/opacity, old display links are invalidated, and Reduce Motion uses brief opacity changes with fixed geometry.
- Music: compact artwork/title header, a read-only elapsed/remaining progress line and centered transport controls. Artwork remains visible until its replacement completes; canceled image tasks cannot overwrite newer content. Real metadata/policy still comes from the existing app services.

Primary study surfaces were upstream `Views/NotchRootView.swift`, `Window/NotchPanel.swift`, and `Views/Music/MusicTabView.swift`.

## Evidence boundary

The full local suite passed: 98 tests in 23 suites, with opt-in live checks skipped where not enabled. After the final pure-SwiftUI progress-bar adjustment, 10 focused geometry/render tests passed. Native component captures were visually inspected for Home in both languages and Music in an explicitly illustrative state. Tests cover stable viewport containment, retargeting continuity, transparent pixels outside the surface, top alignment even while the surface is shorter than its content, and silhouette hit geometry. Scoped review approved the controller, actor/lifecycle and drag-coordinate changes.

This is not live WindowServer proof: frame pacing, pointer click-through and Finder drag/cancel on the physical Mac remain unverified. The running user app was not killed or replaced; normal Quit/reopen loads the new local bundle. No playback command, permission grant, CLI configuration edit, push or publication was performed.
