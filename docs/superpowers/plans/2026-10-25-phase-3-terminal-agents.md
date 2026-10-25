# Terminal and Agent Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent-in-session internal terminals and verified external-agent cards with ordered questions and safe direct responses.

**Architecture:** TerminalSessionStore owns PTYs independently of SwiftUI view lifetime; AgentCoordinator merges adapter events by stable identity. PromptQueue and answer routing reject stale or unsupported requests and publish banners without taking keyboard focus.

**Tech Stack:** SwiftTerm exact v1.99.1, Swift concurrency, SwiftUI/AppKit, native host adapters proved in Phase 1; no CLI setup.

**Spec:** `docs/superpowers/specs/2026-10-25-dynamic-island-macos-design.md`; parent plan `2026-10-25-dynamic-island-implementation.md`.

## Global Constraints

- Codex CLI, Antigravity CLI, Claude Code, Oh My Pi; external hosts VS Code, Orca, Terminal, iTerm2. Supported combinations require live evidence.
- No hook/plugin/configuration changes or alternative launch method required for external discovery.
- FIFO prompt display; incoming question while typing appears as banner without focus theft. Draft input survives the round trip.
- Full-screen default indicator only; idle hidden except pending count; English default, Bahasa Indonesia optional.
- No automatic approvals; never send input to an uncertain session. Hiding panel never terminates PTYs; quitting app never terminates external sessions.

## Review Focus

1. PID reuse and duplicate project/session: `AgentCoordinatorTests.reusedPIDRejectsResponse`.
2. A prompt answered in the original terminal: `PromptQueueTests.resolvedElsewhereCannotBeAnswered`.
3. Permission revoked or owner gone between read/send: `AgentCoordinatorTests.revokedCapabilityPreventsSend`.
4. Banner arriving mid-typing: `PromptPresentationTests.bannerPreservesTerminalAndDraft` plus a live keyboard check.
5. ANSI redraws or partial output look like a question: adapter transcript tests reject ambiguous text as actionable requests.

### Task 1: Internal terminal sessions

**Files:** modify `Package.swift` and resolved lockfile; create `Sources/IslandMac/Services/Terminal/TerminalSessionStore.swift`, `Sources/IslandMac/Features/Terminal/TerminalView.swift`, `Sources/IslandCore/Terminal/TerminalLifecycle.swift`, `Tests/IslandCoreTests/TerminalLifecycleTests.swift`.

**Interfaces:** `@MainActor TerminalSessionStore.create(directory: URL) throws -> SessionID`, `view(for: SessionID) -> NSView`, `close(_ id: SessionID)`, `hasRunningOwnedSessions: Bool`. Own each SwiftTerm `LocalProcessTerminalView` for the whole session, not per SwiftUI render. PTY retains unsent input naturally; avoid a fake line-oriented text input that cannot run interactive CLIs.

- [ ] Write lifecycle tests asserting feature hide/switch does not close an owned session, deliberate close terminates only that owned session, and App Quit requests confirmation when owned processes are running.
- [ ] Run `swift test --filter TerminalLifecycleTests` to FAIL, implement lifecycle transitions, then rerun to PASS.
- [ ] Pin SwiftTerm v1.99.1, inspect that release's public API, and implement the store/view bridge with a user-selected working directory and the user's shell. Set only necessary PTY environment; never log inherited environment or secrets. Do not modify shell configuration.
- [ ] Build/open app; run a harmless shell command, then a supported CLI, resize panel, type an unsent draft, hide/reopen, switch sessions, and verify draft/output continuity. Stop only app-owned test sessions after testing. Commit scoped terminal work.

### Task 2: Agent adapters, FIFO requests, and response routing

**Files:** create `Sources/IslandCore/Agents/AgentAdapter.swift`, `Sources/IslandCore/Agents/PromptQueue.swift`, `Sources/IslandCore/Agents/AgentCoordinator.swift`, `Sources/IslandMac/Services/Agents/HostSessionDiscovery.swift`, `Sources/IslandMac/Services/Agents/CodexAdapter.swift`, `Sources/IslandMac/Services/Agents/ClaudeCodeAdapter.swift`, `Sources/IslandMac/Services/Agents/AntigravityAdapter.swift`, `Sources/IslandMac/Services/Agents/OhMyPiAdapter.swift`, `Sources/IslandMac/Features/Agents/AgentListView.swift`, `Sources/IslandMac/Features/Agents/PromptView.swift`, `Sources/IslandMac/Features/Agents/PromptBannerView.swift`, `Tests/IslandCoreTests/PromptQueueTests.swift`, `Tests/IslandCoreTests/AgentCoordinatorTests.swift`, `Tests/IslandCoreTests/PromptPresentationTests.swift`.

**Interfaces:** consume Phase 1 `SessionID`, `AgentKind`, `HostKind`, `AgentCapabilities`. Define `PromptID`, `AgentPrompt(id: PromptID, sessionID: SessionID, revision: UInt64, text: String, choices: [PromptChoice], acceptsText: Bool)` and `AgentResponse` as choice ID or text. `AgentAdapter.events() -> AsyncStream<AgentEvent>`; `respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt`; `openOrigin(sessionID: SessionID) async throws`. `AgentCoordinator.respond(id: PromptID, revision: UInt64, response: AgentResponse) async throws` rechecks identity, permission, prompt revision, and actual adapter capabilities before sending. Response receipts distinguish sent/confirmed/rejected/unknown; no blind retry of unknown delivery.

- [ ] Write FIFO tests for A then B, resolution removes A, close preserves A, resolved-elsewhere cannot respond, and session exit removes its prompts.
- [ ] Write routing tests for same project/two sessions, reused PID/start time, changed pane, outdated revision, revoked permission, adapter unsupported, unknown receipt without automatic resend. Fake adapters record exactly which session received input.
- [ ] Write presentation tests asserting an incoming prompt in terminal mode produces a banner, retains active session/draft/focus, and only explicit click opens the FIFO head; full screen produces only indicator by default.
- [ ] Run `swift test --filter 'PromptQueueTests|AgentCoordinatorTests|PromptPresentationTests'` to FAIL; implement these exact interfaces and reducer bindings; rerun to PASS.
- [ ] Implement adapters only via Phase 1 verified mechanisms. An unverified agent/host capability remains unavailable with a clear reason; do not implement an unconditional success stub or turn arbitrary terminal text into Allow/Deny buttons.
- [ ] Add redacted fixture tests from controlled sessions for ANSI redraw, split UTF-8/chunked text, ordinary question-like log output, stale prompt, and real choice mapping. Exact expected options must match the relevant CLI version.
- [ ] Implement card list and prompt-only/banners/pending indicator. UI localizes application controls, never rewrites original agent choices or request content. Keep input available when returning to terminal.
- [ ] Build/open app and exercise supported combinations with harmless controlled requests, duplicate sessions, background host tabs, answer from origin, FIFO arrival, and permission loss. Confirm actual receipt; record unsupported/untested combinations in the matrix. Commit scoped work/evidence.

### Task 3: End-to-end acceptance and local delivery

**Files:** create `docs/validation/mvp-acceptance.md`, `README.md`; modify build script only if packaging verification exposes defects.

**Interfaces:** consume all preceding services; produce a reproducible `.build/apps/IslandMac.app` and an acceptance table keyed to the spec's 15 criteria, each with pass/fail/unverified and evidence.

- [ ] Run `swift test` and `scripts/build-app.sh`; fix real failures before claiming a build exists. Verify app resources, languages, dependency lockfile, and stable bundle identifier.
- [ ] Perform normal desktop/full-screen hover, Spotify control, real file drop/cancel, shelf relaunch, owned terminal continuity, real agent FIFO response, banner focus preservation, and permissions checks. Do not replace them with fixture-only PASS.
- [ ] Check both locales at compact panel sizes and the available display scaling. Check reduce motion, keyboard focus indicators, and that a hidden panel does not intercept ordinary menu bar clicks.
- [ ] Test Quit with owned sessions and confirm external sessions remain untouched. Report the controlled Mac-restart shelf test as pending until the user chooses to perform it.
- [ ] Write launch/use/permissions instructions and the actual support matrix. Explicitly identify gaps; incomplete external-agent or file-delivery requirements prevent claiming the full MVP is complete.
- [ ] Commit only implementation/docs from this task. Deliver the local app path and verification summary; do not upload, push, notarize, or publish.
