# Native Shell, Spotify, Settings, and Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a local usable island with configurable hover, music-first Home, English/Indonesian settings, real Spotify controls, and persistent file handoff.

**Architecture:** A deterministic reducer manages opening/closing without owning processes; MainActor AppKit controllers render its state. Spotify and file-shelf stores feed SwiftUI views; atomic local persistence survives relaunch.

**Tech Stack:** SwiftUI, AppKit NSPanel, Foundation, UserDefaults, String Catalog, persistent Application Support storage, SwiftPM `.app` bundling.

**Spec:** `docs/superpowers/specs/2026-10-25-dynamic-island-macos-design.md`; parent plan `2026-10-25-dynamic-island-implementation.md`. Requires Phase 1 native evidence; unresolved agent gates stay visible even if this phase proceeds independently.

## Global Constraints

- Home prioritizes Spotify, with small agent/file summaries beside it. Horizontal content-sized panels, cards without decorative borders.
- Default English; Bahasa Indonesia optional; open 450 ms/close 1,000 ms; full-screen prompts default to indicator only.
- Idle is hidden; pending questions may leave a small indicator. Hover opens Home; drag opens only the drop zone.
- Files default to temporary copy, optional original reference; persist across app quit and Mac restart; never delete originals.
- No global shortcut; no backend; one selected screen with built-in screen default; no Xcode installation or publication.

## Review Focus

1. Late timers firing after re-entry: `IslandReducerTests.staleCloseDoesNotHideReopenedPanel`.
2. Relaunch during shelf manifest write: `FileShelfTests.interruptedWriteKeepsPreviousManifest`.
3. Unavailable/moved original reference: `FileShelfTests.missingReferenceIsUnavailableNotDeleted`.
4. Spotify not running/Automation denied: fake-client tests and visible live check distinguish unavailable/denied from playing.
5. Drop cancellation/unknown completion: `FileShelfTests.unconfirmedDeliveryRetainsOwnedCopy`.

### Task 1: Shell, persisted settings, and localization

**Files:** create `Sources/IslandCore/Presentation/IslandReducer.swift`, `Sources/IslandCore/Settings/SettingsStore.swift`, `Sources/IslandMac/App/IslandApp.swift`, `Sources/IslandMac/Panel/IslandPanelController.swift`, `Sources/IslandMac/Panel/PointerMonitor.swift`, `Sources/IslandMac/Features/Settings/SettingsView.swift`, `Sources/IslandMac/Resources/Localizable.xcstrings`, `scripts/export-localizations.swift`, `Resources/App-Info.plist`, `Tests/IslandCoreTests/IslandReducerTests.swift`, `Tests/IslandCoreTests/SettingsStoreTests.swift`; modify `Package.swift`, `scripts/build-app.sh`.

**Interfaces:** `IslandSettings: Codable` stores language en/id, openDelayMilliseconds=450, closeDelayMilliseconds=1000, fullScreenPrompts=.indicator, fileStorage=.copy. `SettingsStore.load() throws -> IslandSettings` and `save(_:) throws`. `IslandReducer.reduce(state: inout IslandState, event: IslandEvent) -> [IslandEffect]`; generation-token timers prevent stale transitions. Modes: hidden/home/feature/prompt/drop with a pending indicator independent from mode. Input/drag locks prevent timer closure; banner does not change terminal mode.

- [ ] Write reducer tests for 450/1,000 timing effects, re-entry cancellation, hidden idle, drag-only, full-screen indicator, prompt-only, and stale close-token rejection. Write persistence tests for English/defaults, round-trip id, and safe recovery from invalid data.
- [ ] Run `swift test --filter 'IslandReducerTests|SettingsStoreTests'` to FAIL, implement the pure state/settings interfaces, then run to PASS.
- [ ] Implement NSPanel with geometry from Phase 1, event monitor lifecycle cleanup, app Menu Bar control to access settings/quit, and SwiftUI feature routing. Do not terminate session services when hiding/replacing a view.
- [ ] Implement String Catalog keys with en/id UI strings and an explicit app locale. Preserve filenames, commands, and agent content. If CLT cannot compile the catalog, export en/id `.strings` from that same source; do not require Xcode for local probes or duplicate independent translation sources.
- [ ] Extend `scripts/build-app.sh` to package IslandMac, resources, versioned Info.plist, and a stable bundle identifier. Full Xcode, Developer ID distribution, and notarization remain separate work. Inspect resource bundling and permission behavior on this machine rather than assume ad-hoc signing preserves grants.
- [ ] Run `swift test` and `scripts/build-app.sh`; open the resulting app, check hover/full screen, quit/relaunch settings retention, both locales, focus, and no accidental invisible click interception. Commit scoped shell/settings files.

### Task 2: Real Spotify and music-first Home

**Files:** create `Sources/IslandCore/Music/SpotifyTypes.swift`, `Sources/IslandMac/Services/Spotify/SpotifyService.swift`, `Sources/IslandMac/Features/Home/HomeView.swift`, `Sources/IslandMac/Features/Music/MusicView.swift`, `Tests/IslandCoreTests/SpotifyStateTests.swift`, `Tests/IslandIntegrationTests/SpotifyLiveTests.swift`.

**Interfaces:** `SpotifySnapshot` stores availability, playback state, title, artist, artwork URL, position/duration. `SpotifyClient.snapshot() async throws -> SpotifySnapshot`, `perform(_ command: SpotifyCommand) async throws` for toggle/previous/next. One observable `SpotifyStore` feeds both screens. Native client uses only Phase 1 proven interfaces.

- [ ] Write tests for unavailable, denied, paused/playing, and command failure. Assert Home/Music consume one snapshot; no sample song substitutes for absent live data.
- [ ] Run `swift test --filter SpotifyStateTests` to FAIL, implement minimal types/store and native client, then rerun to PASS.
- [ ] Build compact Home: dominant music at left, agent summary and file thumbnails/count at right. Summaries navigate to features. Before agent integration, show unavailable/unsupported or no detected sessions, not fixture activity.
- [ ] Add Music view and controls, artwork cache with bounded size, and state refresh that stops unnecessary polling when inactive. No Spotify auto-launch or automatic playback on app launch.
- [ ] Run opt-in `ISLAND_LIVE_TESTS=1 swift test --filter SpotifyLiveTests` only when Spotify/permissions are available; skipped means unverified. Check deliberate buttons against actual Spotify and switch both languages. Commit scoped media/Home work.

### Task 3: Persistent one-transfer file shelf

**Files:** create `Sources/IslandCore/Files/FileShelf.swift`, `Sources/IslandMac/Services/Files/NativeFileAccess.swift`, `Sources/IslandMac/Services/Files/FileDragCoordinator.swift`, `Sources/IslandMac/Features/Files/FileShelfView.swift`, `Sources/IslandMac/Features/Files/DropZoneView.swift`, `Tests/IslandCoreTests/FileShelfTests.swift`; modify Home bindings and validation evidence.

**Interfaces:** `ShelfItem: Codable, Identifiable` stores UUID, display name, storage mode, app-owned relative path or persistent bookmark, and availability. `FileShelf.importFiles(_ urls: [URL], mode: FileStorageMode) async throws -> [ShelfItem]`; `remove(_ id: UUID) async throws`; `completeDelivery(_ id: UUID, receipt: DeliveryReceipt) async throws`; manifest writes use atomic replacement under Application Support/IslandMac.

- [ ] Write meaningful filesystem tests using isolated directories: duplicate names retain distinct UUIDs; copy import survives original deletion; reference import reports missing source; removal leaves original untouched; interrupted manifest replacement retains prior valid manifest; cancelled/failed/unconfirmed delivery retains the copy.
- [ ] Run `swift test --filter FileShelfTests` to FAIL, implement shelf lifecycle and persistence, then rerun to PASS. Do not load whole large files into memory or follow directory/symlink trees without an explicit bounded policy.
- [ ] Implement actual drop-only state with no existing thumbnails or navigation during drag. On normal Files view, show icon/thumbnail tiles with filename, selection, drag-out, and remove. Use system thumbnail facilities where available and a file icon otherwise.
- [ ] Wire native drag lifecycle to the acknowledgement proved in Phase 1. If no safe acknowledgement was proved, retain copies and report the acceptance gap; do not silently implement destructive best guesses.
- [ ] Build/open app; verify Finder import, cancelled drag, successful supported handoff, unavailable reference, duplicate names, quit/relaunch and a controlled restart check. Restart requires a user-chosen time; do not restart the Mac automatically. Commit code and truthful evidence; unperformed restart remains pending.
