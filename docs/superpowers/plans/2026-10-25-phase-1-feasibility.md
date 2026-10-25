# Native Feasibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove or rule out external-agent prompt response, full-screen panel operation, and safe drag-delivery acknowledgement without altering CLI setup.

**Architecture:** Compile small native probes behind explicit scenario arguments and keep reusable identity types in IslandCore. Probes expose observed capabilities, not inferred status; no approval answer is sent to an arbitrary existing user session.

**Tech Stack:** Swift 6.2 manifest, SwiftPM, AppKit, Foundation, ApplicationServices; minimum macOS 14; native arm64 local `.app`.

**Spec:** `docs/superpowers/specs/2026-10-25-dynamic-island-macos-design.md`; parent plan `2026-10-25-dynamic-island-implementation.md`.

## Global Constraints

- English default; Bahasa Indonesia supported in the app. No CLI hook/plugin/configuration changes.
- Target MacBook Pro M1 without notch. Only macOS permissions are acceptable integration setup.
- Test Codex CLI, Antigravity CLI, Claude Code, Oh My Pi across VS Code, Orca, Terminal, and iTerm2 where installed.
- No actual permission prompt is approved without an explicit user click for that exact request.
- Raw terminal transcripts, process environment, tokens, and full command-line arguments must not be logged in evidence.

## Review Focus

1. PID reuse: `SessionIdentityTests.reusedPIDIsDifferentSession`.
2. Hidden/background tabs expose different capabilities: live matrix records foreground and background independently.
3. Revoked Accessibility/Automation permissions: live probe must show denied/unavailable and send nothing.
4. Focus and full screen: live panel probe must preserve typed text and avoid taking focus on notification.
5. Drag acceptance without confirmed delivery: `DeliveryReceiptTests.unconfirmedTransferRetainsCopy` plus Finder/native drag probe.

### Task 1: External-session identity and capability probe

**Files:** create `Package.swift`, `.gitignore`, `Sources/IslandCore/Agents/AgentTypes.swift`, `Sources/IslandProbe/main.swift`, `Sources/IslandProbe/AgentProbe.swift`, `Sources/IslandProbe/SessionIdentityResolver.swift`, `scripts/build-app.sh`, `Resources/Probe-Info.plist`, `Tests/IslandCoreTests/SessionIdentityTests.swift`, `docs/validation/agent-capabilities.md`.

**Interfaces:** produce `SessionID: Hashable, Codable` combining owner instance ID, PID, process start time, and terminal session key; `AgentKind`, `HostKind`, `AgentCapabilities` with separate discovery/readPrompt/sendResponse/openOrigin flags. Produce `CapabilityObservation(sessionID: SessionID?, capability: String, outcome: ProbeOutcome, evidence: String)` where outcomes are observed/unsupported/unavailable/denied; no boolean success for untested checks.

- [ ] Create the minimal SwiftPM manifest, IslandCore/IslandProbe target directories, and test target so `swift test` discovers the suite. Add a placeholder source file without identity behavior; do not diagnose a missing package as the expected test failure.
- [ ] Write identity tests: same PID/different start time differs; same project/two pane keys differs; unknown owner cannot produce a sendable identity.
- [ ] Run `swift test --filter SessionIdentityTests`; expect missing identity symbols or failed identity assertions, not a package/configuration failure.
- [ ] Implement the types and minimal resolver. Create an `IslandProbe` executable with `inventory`, `agent`, `panel`, `drag`, `spotify` scenario names; dispatch only the implemented scenario and report unsupported otherwise. Bundle Info.plist includes purpose strings for Automation; no environment dump or shell interpolation.
- [ ] Run the identity tests; expect PASS. Package/open the probe with `scripts/build-app.sh --probe` then `open .build/apps/IslandProbe.app --args inventory`.
- [ ] Inspect executable versions and installed host locations without launching/mutating user agent sessions. Inspect public documented host APIs and actual accessibility/session surfaces. Do not read credential files or use private agent databases as a convenient integration.
- [ ] Build `agent` probe to inspect one explicitly selected session. Record a matrix row per agent/host with exact tested version and scope. Do not claim background support based on foreground success. Entries not exercised remain untested; missing applications are unavailable.
- [ ] Exercise duplicate sessions, background tab, resolved/expired prompt, and permission revocation on controlled harmless sessions. Sending a response is a distinct live verification step, targeted to a harmless prompt the user can see and explicitly answer. Record unsupported cases honestly.
- [ ] Commit scoped identity/probe/evidence files. Gate: establish which exact combinations can fulfill discovery, prompt extraction, and response routing without CLI setup. Ask for a scope change only if evidence requires it.

### Task 2: Panel geometry, focus, and full screen

**Files:** create `Sources/IslandProbe/PanelProbe.swift`, `Sources/IslandCore/Presentation/PanelGeometry.swift`, `Tests/IslandCoreTests/PanelGeometryTests.swift`, `docs/validation/panel-behavior.md`.

**Interfaces:** consume host inventory; produce `PanelGeometry.triggerRect(screen: CGRect, menuBarHeight: CGFloat) -> CGRect` and `panelRect(screen: CGRect, size: CGSize) -> CGRect`. Trigger is centered with menu-bar height; panel top aligns to selected screen's top.

- [ ] Write geometry tests using a 1440×900 screen, a 24-point menu bar, and a 680×180 panel; assert centered horizontal bounds, exact top edge, and no off-screen bounds with a nonzero secondary-screen origin.
- [ ] Run `swift test --filter PanelGeometryTests`; expect FAIL, then implement geometry and rerun to PASS.
- [ ] Implement a small NSPanel probe that can show without stealing focus and become key only for deliberate terminal/input interaction. Avoid a screen-sized invisible hit-testing window.
- [ ] Run `open .build/apps/IslandProbe.app --args panel`; verify on normal desktop and a full-screen app: hover target, native Spaces switching, menu bar access, no focus theft, deliberate typing, and pointer exit. Record actual behavior and limitations.
- [ ] Commit the probe and evidence. If full-screen targeting fails, resolve native window configuration before promising acceptance.

### Task 3: Drag delivery and local Spotify evidence

**Files:** create `Sources/IslandCore/Files/DeliveryReceipt.swift`, `Tests/IslandCoreTests/DeliveryReceiptTests.swift`, `Sources/IslandProbe/DragProbe.swift`, `Sources/IslandProbe/SpotifyProbe.swift`, `docs/validation/file-delivery.md`, `docs/validation/spotify.md`.

**Interfaces:** produce `DeliveryReceipt` cases `.confirmed`, `.cancelled`, `.failed`, `.unconfirmed` and `canRemoveShelfCopy(receipt: DeliveryReceipt) -> Bool`; only confirmed permits removal. Produce `SpotifyObservation` with application availability, playback state, metadata availability, artwork availability, and supported controls recorded independently.

- [ ] Write receipt tests asserting false for cancelled/failed/unconfirmed and true only for confirmed. Run `swift test --filter DeliveryReceiptTests` to FAIL, implement the predicate, then rerun to PASS.
- [ ] Implement drag probe with an app-owned harmless sample, Finder target, cancellation target, and native drag-session callbacks. Demonstrate which event guarantees the consumer no longer needs the app-owned source. Never delete the last copy merely because drag-end reports an accepted operation.
- [ ] Run native Finder copy/cancel/failed-target scenarios; compare the resulting file with the original sample. If no sufficient acknowledgement exists, document the retention-safe limitation and request a product decision before changing one-transfer semantics.
- [ ] Implement read-only Spotify probe using its installed scripting dictionary, then explicit user-controlled playback controls. Check not-running, paused, playing, metadata, artwork, denied Automation; never launch Spotify or start audio just to inspect availability.
- [ ] Run `swift test` and rebuild all probe scenarios. Commit scoped changes and write the Phase 1 go/no-go summary to the capability evidence. Unit PASS must remain separate from untested or blocked live checks.
