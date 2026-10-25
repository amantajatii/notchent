# Dynamic Island macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a local native macOS island with Spotify-first Home, a persistent file shelf, an interactive terminal, and verified external-agent prompts without CLI setup.

**Architecture:** SwiftUI renders content inside an AppKit NSPanel; a pure Swift IslandCore library owns presentation state, settings, file metadata, and request identity. Native services implement Spotify, filesystem, terminal, and external-session adapters. Three sequential plans isolate risky feasibility work from the application shell and agent subsystem.

**Tech Stack:** Swift 6.2 package manifest, SwiftUI, AppKit, Foundation, ApplicationServices, SwiftTerm exact v1.99.1, SwiftPM, local app-bundle scripts; minimum macOS 14 as a builder choice.

**Spec:** `docs/superpowers/specs/2026-10-25-dynamic-island-macos-design.md` — approved 25 October 2026, including native Swift stack.

## Global Constraints

- Target awal: MacBook Pro M1 tanpa notch milik pengguna.
- Bahasa antarmuka: English dan Bahasa Indonesia; default English.
- Spotify merupakan sumber musik prioritas MVP.
- Tidak ada shortcut global khusus island pada MVP.
- Tanpa pemasangan plugin/hook, perubahan konfigurasi CLI, atau perubahan cara menjalankan agent sebagai syarat integrasi sesi eksternal.
- Delay awal: membuka 450 ms, menutup 1.000 ms; keduanya dapat diatur dan disimpan.
- Default full screen: indikator kecil untuk pertanyaan agent.
- Default file storage: temporary copy; original file reference tersedia.
- File titipan tetap tersedia setelah aplikasi berhenti dan Mac restart. Menghapus titipan tidak menghapus file asli.
- Island horizontal, tinggi mengikuti isi, card tanpa border dekoratif, Home mengutamakan musik.
- Jangan memasang dependensi global, mengubah instalasi agent, membaca credential, atau mengunggah isi sesi.
- Implementasi lokal; tidak ada push, publikasi, deployment, atau pemasangan Xcode otomatis.

## Review Focus

1. PID reuse and duplicate sessions must never route an answer to another project: Phase 1 Task 1 and Phase 3 Task 2.
2. Revoked system permission must disable interaction rather than synthesize a working status: Phase 1 Task 1 and Phase 3 Task 2.
3. A canceled, unconfirmed, or failed file transfer must retain the application-owned copy: Phase 1 Task 3 and Phase 2 Task 3.
4. Focus changes, stale hover timers, and incoming prompts must not swallow terminal input: Phase 1 Task 2 and Phase 3 Tasks 1–2.
5. Shutdown/relaunch during a shelf write must retain a consistent manifest and avoid deleting originals: Phase 2 Task 3.

## Starting evidence

Checked locally on 25 October 2026:

- Checkout contains the approved spec and no application source; it is not currently a Git repository.
- `xcode-select -p`: `/Library/Developer/CommandLineTools`; Swift 6.4, arm64, macOS 27.0.1.
- Found `codex`, `claude`, `agy`, and `omp` executables. Their presence is not proof of integration; `agy`/`omp` identity must be checked.
- Spotify, Orca, and Visual Studio Code found in `/Applications`. iTerm2 was not found at the single conventional `/Applications/iTerm.app` path checked; inspect other installed locations before declaring it unavailable.
- SwiftTerm release checked: [v1.99.1](https://github.com/migueldeicaza/SwiftTerm/releases/tag/v1.99.1). Pin the release and resolve its manifest, not mutable `main`.
- Full Xcode is not assumed. Build/probe via SwiftPM and a local `.app` wrapper first. If a required SDK tool is absent, report its exact name before any installation.

## File and module map

| Location | Responsibility |
| --- | --- |
| `Package.swift` | IslandCore library, IslandMac executable, test targets, native probes |
| `Sources/IslandCore/Presentation/` | Panel state reducer and ordered request queue |
| `Sources/IslandCore/Agents/` | Stable session identity, capabilities, prompt/response types |
| `Sources/IslandCore/Settings/` | Codable settings and persistence interface |
| `Sources/IslandCore/Files/` | Persistent shelf lifecycle and delivery acknowledgement |
| `Sources/IslandMac/App/` | Application lifecycle and service composition |
| `Sources/IslandMac/Panel/` | NSPanel, screen geometry, event monitoring |
| `Sources/IslandMac/Features/` | Home, Music, Files, Agents, Terminal, Settings views |
| `Sources/IslandMac/Services/` | Spotify, permissions, terminal, filesystem, external adapters |
| `Sources/IslandMac/Resources/` | String catalog and generated en/id resources |
| `Sources/IslandProbe/` | Disposable, explicit native feasibility scenarios |
| `Tests/IslandCoreTests/` | Meaningful state, identity, persistence, queue tests |
| `Tests/IslandIntegrationTests/` | Opt-in real service checks; never infer pass from skipped checks |
| `scripts/build-app.sh` | Reproducible local app packaging and resource copy |
| `scripts/export-localizations.swift` | Export approved catalog strings for CLT builds if required |
| `docs/validation/` | Actual capability matrix and manual verification evidence |

## Sequential plans and gates

- [ ] Execute [Phase 1: native feasibility](2026-10-25-phase-1-feasibility.md). Deliver a capability matrix, small probes, and explicit decision on whether external-prompt requirements are achievable.
- [ ] If feasibility contradicts a core requirement, present evidence and options to the user before changing that requirement. Independent proven features may continue; no unsupported full-MVP completion claim.
- [ ] Execute [Phase 2: shell, Spotify, settings, files](2026-10-25-phase-2-native-shell.md). Deliver a usable local app with working music and persistent file shelf.
- [ ] Execute [Phase 3: terminal and agents](2026-10-25-phase-3-terminal-agents.md). Deliver supported real sessions and validated prompt responses, then evaluate all acceptance criteria.

Each phase's tests run once after meaningful changes; rerun broader checks only after a new failure or change. Native permission/full-screen/Spotify/drag checks must run in a visible real application; passing pure unit tests is insufficient evidence.

## Version control and execution

At execution start, inspect parent instructions and initialize a local Git repository if still absent. Do not create a worktree for an empty repository. Commit the existing design/plans separately, then make scoped commits per tested task. Keep unrelated or future work untracked/unstaged as appropriate. Ignore build artifacts and probe output containing local user data; never commit credentials or raw terminal transcripts.

No application code has been written by this plan. Select execution approach after the plan handoff: Native executes in this chat; Subagent-driven assigns an implementation task and independent review per task.
