# Agent capability probe — 2026-10-25

**Phase status: foundation ready; live integration gate pending.** Task 1 foundation acceptance does not complete the controlled live feasibility checks. **No agent/host combination is verified for prompt extraction or response routing.** The no-CLI-setup feasibility gate remains open. No hooks, plugins, global installations, credentials, environment, private session databases, or raw transcripts were accessed.

## Reproduce

- `scripts/test.sh --filter SessionIdentityTests` (focused) or `scripts/test.sh` (full suite).
- `scripts/build-app.sh --probe`
- `open .build/apps/IslandProbe.app --args inventory`
- `.build/apps/IslandProbe.app/Contents/MacOS/IslandProbe inventory` for JSON stdout.
- `IslandProbe agent --pid <positive PID>` inspects only one explicitly selected controlled process's birth time. It does not infer an owner/pane or accept arbitrary response text.
- `panel`, `drag`, and `spotify` dispatch to explicit unsupported observations.

Swift 6.4 CLT uses swiftbuild by default, which failed to find XCTest. XCTest was also absent in native mode. Bundled Swift Testing works with native mode, `--disable-xctest`, and explicit developer framework search/rpath flags; `scripts/test.sh` applies these locally using `xcode-select -p`. No toolchain changes. Native engine emits this exact diagnostic:

> warning: '--build-system native' has been deprecated and will be removed in a future release; please report an issue at https://github.com/swiftlang/swift-package-manager/issues if you are unable to adopt the default build system.

Migration follow-up: reproduce CLT framework discovery with the default swiftbuild engine and report the failure upstream; migrate both scripts to the default engine once it resolves bundled Swift Testing and links the probe successfully. Keep the warning visible until then. Minimum macOS 14 matches the plan and bundled Testing.

## Observed inventory

| Component | Exact version | Scope |
| --- | --- | --- |
| Codex CLI | 0.164.0 | `codex --version`; installed executable only |
| Claude Code | 2.1.258 | `claude --version`; installed executable only |
| Antigravity CLI (`agy`) | 1.4.7 | `~/.local/bin/agy --version`, exit 0; executable contains Antigravity-branded metadata |
| Oh My Pi / `omp` alias | 18.12.6 | `/opt/homebrew/bin/omp --version` → `omp/18.12.6`, exit 0; Homebrew symlink and formula identify `omp.sh` coding agent |
| VS Code | 1.143.1 | `/Applications/Visual Studio Code.app` Info.plist |
| Orca | 1.4.238 | `/Applications/Orca.app` Info.plist; bundle ID `com.stablyai.orca` |
| Terminal | 2.15 | `/System/Applications/Utilities/Terminal.app` Info.plist |
| iTerm2 | 3.7.3 | `~/Applications/iTerm.app` Info.plist |

The executable inventory observed `AXIsProcessTrusted() == true` for this execution context. It did not request permission. No matching running host was returned by `NSWorkspace.shared.runningApplications` in that execution context; no AX attribute values or terminal text were read. This is not proof those applications are closed in another GUI context. Application-level AX attribute-name enumeration is implemented for matching running hosts, but that branch was not exercised. Bundle open returned exit 0; LaunchServices execution output and bundle-specific permissions were not observed. The bundle is a short-lived LSUIElement executable, with stdout JSON, no visible window.

Selected controlled shell metadata probe observed a process birth time through `proc_pidinfo`; no agent session selected. Session IDs combine owner instance, PID, microsecond process birth time, and terminal pane/session key. Unknown owner or missing key resolves to nil. Caller-supplied identity components are not discovery evidence or permission to send; this probe offers no send operation.

Alternate executable verification used subprocess argument arrays with a 10-second timeout for `--version` and `--help`. `agy --help` identifies agent CLI session options; embedded executable metadata includes Antigravity-branded assets. `/opt/homebrew/bin/omp` resolves to `../Cellar/omp/18.12.6/bin/omp`; its Homebrew formula states “Coding agent with the IDE wired in” and homepage `https://omp.sh`, whose [official site](https://omp.sh/) currently brands the product as `omp`. The requested Oh My Pi alias is recorded with that current executable identity, without treating it as an exercised integration. No session was launched by these version/help checks.

## Capability matrix

D = session discovery, R = prompt extraction, S = response routing, O = open origin. `untested` is evidence status, not a successful boolean. Installed host/version applies to each row. The requested alternate CLI names `agy` and `omp` were inspected directly; absence of `antigravity` or `pi` on PATH is not evidence of missing installations. These checks establish executable inventory only.

| Agent (exact CLI version) | Host (exact version) | D | R | S | O | Tested scope |
| --- | --- | --- | --- | --- | --- | --- |
| Codex 0.164.0 | VS Code 1.143.1 | untested | untested | untested | untested | inventory only |
| Codex 0.164.0 | Orca 1.4.238 | untested | untested | untested | untested | inventory only |
| Codex 0.164.0 | Terminal 2.15 | untested | untested | untested | untested | inventory only |
| Codex 0.164.0 | iTerm2 3.7.3 | untested | untested | untested | untested | inventory only |
| Claude Code 2.1.258 | VS Code 1.143.1 | untested | untested | untested | untested | inventory only |
| Claude Code 2.1.258 | Orca 1.4.238 | untested | untested | untested | untested | inventory only |
| Claude Code 2.1.258 | Terminal 2.15 | untested | untested | untested | untested | inventory only |
| Claude Code 2.1.258 | iTerm2 3.7.3 | untested | untested | untested | untested | inventory only |
| Antigravity (`agy`) 1.4.7 | VS Code 1.143.1 | untested | untested | untested | untested | executable inventory only |
| Antigravity (`agy`) 1.4.7 | Orca 1.4.238 | untested | untested | untested | untested | executable inventory only |
| Antigravity (`agy`) 1.4.7 | Terminal 2.15 | untested | untested | untested | untested | executable inventory only |
| Antigravity (`agy`) 1.4.7 | iTerm2 3.7.3 | untested | untested | untested | untested | executable inventory only |
| Oh My Pi / `omp` 18.12.6 | VS Code 1.143.1 | untested | untested | untested | untested | executable inventory only |
| Oh My Pi / `omp` 18.12.6 | Orca 1.4.238 | untested | untested | untested | untested | executable inventory only |
| Oh My Pi / `omp` 18.12.6 | Terminal 2.15 | untested | untested | untested | untested | executable inventory only |
| Oh My Pi / `omp` 18.12.6 | iTerm2 3.7.3 | untested | untested | untested | untested | executable inventory only |

Runtime outcomes use observed / unsupported / unavailable / denied. Unexercised checks use unavailable with explicit unverified evidence when emitted; unsupported means this probe lacks the adapter, not that the host can never support it. `AgentCapabilities` flags default false and must not be interpreted as test outcomes; observations carry evidence.

## Public surface research

### Codex shared app-server follow-up — 2026-10-26

The installed Codex 0.164.0 exposes `codex app-server proxy`, a public stdio proxy to its already-running shared app-server. The matching installed schemas contain loaded-thread listing, running-thread resume, typed approval/user-input requests, and resolved notifications. Matching upstream release source supports additive subscribers and replay of ordinary pending requests. This establishes a plausible integration route, not an active capability.

At inspection, `codex app-server daemon version` failed because `~/.codex/app-server-control/app-server-control.sock` did not exist. No Codex CLI session was running for a controlled test. No CLI or daemon was started, no thread metadata/transcript was read, and no live request was attached or answered. Consequently the shipped adapter remains unavailable and Codex prompt display/response are **not implemented**. Do not infer working UI integration from protocol schemas or upstream source.

Before enabling an adapter, validate with a user-owned harmless test thread: metadata-only discovery, additive subscribe while the original CLI remains usable, pending request replay, answer from each client, first-response-wins/dismissal, disconnect/reconnect, thread unload race, and daemon restart. Only ordinary approval and user-input request types with exact UI representations may be actionable; never expose native user-verification requests or apply broader session/policy approvals implicitly. Resume changes daemon client attribution and can affect thread lifecycle/idle eviction; implementation must document and bound that subscription.

- [VS Code API](https://code.visualstudio.com/api/references/vscode-api) exposes terminal objects and sendText inside extensions. This is not evidence of an external native macOS interface; installing an extension would violate this phase's setup constraint.
- [VS Code shell integration](https://code.visualstudio.com/docs/terminal/shell-integration) documents shell state integration; no installation/configuration was performed.
- [iTerm2 session API](https://iterm2.com/python-api/session.html) documents session IDs and session operations. API enablement, identity mapping, and authorization were not exercised.
- [Apple Terminal automation](https://support.apple.com/en-kw/guide/terminal/trml1003/mac) documents AppleScript automation. Automation permission and stable pane mapping remain untested.
- [Orca terminal documentation](https://www.onorca.dev/docs/terminal) describes panes and agent state. A documented supported external prompt/response interface was not established. Several unrelated products share the name Orca; their REST APIs are not evidence for `com.stablyai.orca`.

## Remaining controlled live checks

Duplicate sessions, background tabs, resolved/expired prompts, permission revocation, and a response to an explicitly approved harmless prompt are all **untested**. No foreground success is claimed, so no background capability is inferred. A later controlled GUI run must verify owner and terminal session key, revalidate process birth time before action, and reject stale/expired prompt routes. Do not answer any live agent permission request automatically. No production integration recommendation can yet be made from this inventory.

## Phase 1 aggregate gate — Task 3, 2026-10-25

Receipt policy: 4/4 receipt tests pass (12/12 package tests); app rebuild passes. Native drag callback and promised-file destination writing scenes implemented. Finder copy/cancel/rejection and full-screen UI acceptance remain unverified. **No-go for automatic last-copy deletion or strict one-transfer promises** pending the product retention decision and live evidence. See `file-delivery.md`.

Spotify 1.3.6.1921 is running; read-only no-prompt Automation preflight returns requires-consent (-1744), not denied. State/metadata/artwork and playback commands remain live untested. Conditional implementation go with permission states; no verified live integration claim. See `spotify.md`. Existing agent routing and panel gates above remain unchanged; passing unit tests do not clear their live gates.
