# Agent capability probe — 2026-10-25

**Phase status: foundation ready; live integration gate pending.** Task 1 foundation acceptance does not complete the controlled live feasibility checks. **Codex/Terminal command-approval replay/display is now observed (2026-10-26); response delivery remains unverified.** The no-CLI-setup feasibility gate remains open. No hooks, plugins, global installations, credentials, environment, private session databases, or raw transcripts were accessed.

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
| Codex 0.164.0 | Terminal 2.15 | metadata observed | command approval observed | untested | unavailable | User screenshot + read-only replay; daemon thread identity, pane mapping unavailable |
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

### Terminal login ancestry fix — 2026-10-26

A live Codex CLI process had a Terminal → root-owned login → user shell → Node launcher → native Codex ancestry. The original same-user-only snapshot discarded login, so the external host could not be resolved and the registry hid that candidate. On this installation, PROC_PIDTBSDINFO denies root login metadata even though proc_pidpath works. The scanner now uses public KERN_PROC_PID metadata only to bridge root-owned ancestors; these records cannot become agent candidates or routable sessions. Other users' agents remain excluded. No arguments, environment, terminal contents, or histories are read.

Seven discovery tests passed, including root-login bridging and exclusion of root/other-user agent candidates. The live metadata scan changed from zero to one target-host candidate while the controlled Codex-in-Terminal session remained running. This verifies metadata discovery only; stable external pane mapping and prompt read/reply remain unavailable. The shared Codex daemon also reports running at 0.164.0, but no thread has been subscribed to or answered by this change. Reloading IslandMac is required to use the rebuilt scanner.

### Experimental Codex request adapter — 2026-10-26

The native app now implements a local WebSocket client to the existing default daemon control socket. Important correction to the initial proxy proposal: `codex app-server proxy` is a raw stdio/Unix tunnel, not newline JSON-RPC. Native Network.framework raw Unix transport plus a validated RFC 6455 handshake/framing is used; no dependencies, hooks, shell/CLI config, startup flags, or automatic permission grants are added. The socket must belong to the current user with no group/other permissions.

The adapter requires a same-user TTY Codex process before observing the daemon. It lists loaded IDs, reads metadata with includeTurns:false, and rejoins only active loaded threads using excludeTurns:true with no config overrides. Loaded membership is checked before/after rejoin. A post-join active-state check gates replay publication. This reduces but cannot eliminate the public protocol's non-atomic unload/cold-resume race. Thread subscriptions change client attribution and idle retention. Prompt UI shows the actual daemon thread name, project and short ID; it does not claim that the thread is mapped to a particular detected TTY pane. Supplied source metadata was vscode even for the controlled CLI test, so it is not used to fabricate that association.

Supported request shapes: commandExecution/requestApproval with explicit command/cwd, showing original reason and additional permission context; only advertised one-time accept/decline/cancel decisions are offered. requestUserInput supports one non-secret question with exact label mapping/free text when permitted. Multi-question/secret forms, file changes, permissions requests, legacy requests and MCP/native user-verification elicitation remain unsupported. Exact original string/integer RPC IDs are retained, scoped to connection/daemon birth/thread/subscription. Submissions are latched; bytes written return sent, not confirmed. Resolved notifications dismiss pending requests regardless of which client won. Reconnect discards old pending identities. Queue updates have one streaming publisher while the app is running.

Evidence: four WebSocket parser tests, four typed-request mapping tests, a queue-stream test, and the existing safety/PTY suite pass. A native opt-in runtime test successfully completed the WebSocket handshake, initialize, initialized and loaded-thread listing against daemon 0.164.0. The full local suite reports 89 tests in 22 suites passed, including one Spotify opt-in skip (see current test log). Two controlled user-named Sapa pengguna loaded threads were joined and unsubscribed read-only; both reported idle and no pending server request was replayed. No approval was answered. Therefore current request capture, human-selected reply, CLI convergence, reconnect/unload races, and GUI automatic display remain UNVERIFIED, not PASS.

### Advertised approval options and live capture — 2026-10-26

The user supplied a live screenshot of the same command-approval request in Terminal and IslandMac. A read-only join of the active named test thread replayed item/commandExecution/requestApproval ID 2 with availableDecisions exactly [accept, {acceptWithExecpolicyAmendment: {execpolicy_amendment: [pwd]}}, cancel]. No response was sent. This is positive evidence of replay and GUI request presentation for this controlled case; it supersedes the earlier idle/no-pending probe boundary.

The earlier adapter discarded object-shaped decisions, leaving only two buttons. The current adapter preserves the order and original typed payload for every known offered decision: accept, acceptForSession, decline, cancel, execpolicy amendment, and network-policy amendment (allow/deny). Session/persistent scope and exact prefix/host are explicitly shown. Nothing is granted automatically and no broader decision is synthesized. Twenty focused mapping/routing tests passed, including the observed three-option fixture, exact policy payload, and malformed/duplicate rejection. The new three-button rendering and actual human response delivery are not yet verified live.

## Discovery repair — 2026-10-27

The shared-daemon connection no longer depends on an unrelated TTY Codex process. It still requires the same-user, launchd-owned daemon under the expected package directory and a private same-user control socket. Verified active daemon threads now feed the visible registry, using thread-specific card identities. Codex desktop host ancestry (ChatGPT.app / Codex.app) is recognized even without a TTY. Such process cards explicitly retain unknown activity and unavailable session connection; they do not gain reply capabilities from the daemon's connection alone.

Live checks found the shared daemon reachable but reporting zero loaded threads. Desktop Codex process ancestry was present. Regression checks cover non-TTY daemon selection, wrong-owner and sibling-path rejection, desktop metadata without fabricated session identity, and distinct cards for threads sharing a daemon PID. The Agents panel now uses the same 520-point content width as Home, removes extra empty-state top padding and caps height according to card count. Home's Agents summary also has smaller padding.

## Compact list and drill-down — 2026-10-27

Agents now opens as borderless two-line rows with a fixed-size status marker and disclosure. Selecting a row shows metadata/support details and a Back control, with an owned-terminal action only when an owned running target exists. Selection stores a stable card identity and falls back to the list when that identity disappears. Diagnostic paragraphs moved out of the list. No progress, token use, transcript summary or task title is fabricated for process-only entries. Existing pending-request publication still uses the reducer's automatic prompt presentation, including its input/drag/full-screen protections; a matching detail can explicitly open the current pending request.

## Desktop session observation — 2026-10-27

Actual process transport inspection found the desktop app-server uses private stdio and exposes no attachable Unix/TCP listener; the separate shared daemon reports zero loaded threads. The other native executables included an exec-server and a secondary stdio server. The earlier three process cards were not three connected sessions.

An independently implemented read-only observer now enumerates libproc vnode descriptors for same-user native Codex processes and reads only currently open rollout files under the canonical ~/.codex/sessions directory. It never enumerates historical session directories, changes hooks/configuration, duplicates another client's stdio, resumes desktop sessions on another server, or grants approvals. Files must be regular same-user files and cannot be final-component symlinks; process birth is rechecked after reading. Reads are capped at a 64 KiB header and 256 KiB tail per file. Structured session metadata supplies the real session UUID/project; lifecycle records supply activity and bounded completion summaries. Partial records and late completions for another turn cannot fabricate activity. Summary text remains local to the UI and is not logged.

Five live open sessions were found through PID 35582's descriptors. Process-only desktop cards are replaced by session cards, deduplicated against verified daemon threads. These identities are explicitly codex-observed and never registered as reply routes. A desktop session shows read-only support, with a truthful instruction to answer in Codex. Automatic actionable questions still require an actual daemon request; rollout records are not replayed as live prompts. This fixes session monitoring, not the missing desktop interactive bridge.

Native runtime verification: the previous process exited through normal Quit and Close Terminals. The rebuilt app was opened and its Home showed 5 Agents. The Agents list visibly contained four dynamic-island sessions and one notch session, with four Finished states and one Activity unavailable state. These were session UUID/project rows, replacing the old PID-only rows. Parser/discovery/request regression tests passed (23 scoped tests, then 4 observer tests after adding the late-turn guard). Continuous activity can remain unknown when the bounded tail omits its lifecycle record. No desktop question or approval was answered; no interactive desktop bridge is claimed.

## Retained-session clutter fix — 2026-10-27

An open rollout descriptor proves process ownership, not that its conversation is still active. Codex retained completed desktop rollouts and the previous scanner showed all of them indefinitely. The observer now retains working sessions, but only shows completed/interrupted or recently modified unknown-state sessions for 30 seconds. Lifecycle timestamps take precedence over file mtime so touching an old completed file does not revive it. Separate simultaneous working sessions in the same project remain separate. Regression coverage checks expiration, stale touched files, working-session preservation, and unknown-state expiration.

Retention preference update: completed/interrupted sessions now remain visible for 30 minutes from their lifecycle timestamp, as requested. Unknown activity still expires after 30 seconds of file inactivity. Working sessions remain visible. Regression coverage verifies visibility after 28 minutes and expiration after 30 minutes without reviving stale touched files.

## Continue an existing conversation through the official queue — 2026-10-27

The installed 0.164.0 CLI exposes codex queue; matching upstream release source implements thread/queue/add and a shared durable queue watcher. This is different from attaching to a private desktop turn: enqueueing does not resume/fork/start a thread on another app-server. The native app now sends the exact selected session UUID, a new clientUserMessageId, and one literal text input to that official method over the already validated daemon connection. No shell interpolation, model/config/approval override, new thread or automatic message is used. The originating Codex process can consume queued input when ready. Queue acknowledgement is displayed as queued, never as delivered or completed.

The per-session draft survives navigation/hide. Sending is latched against repeated clicks; text clears only when the returned queue item echoes the exact client ID and message. Missing/malformed acknowledgements and transport failure retain the draft and require an explicit user check before unlocking it; there is no automatic retry. Registry membership, supported session identity, payload size and fresh same-user process birth are validated before enqueueing. The Agents panel accepts keyboard focus only through deliberate input and keeps the panel open while typing. Existing final-summary observation supplies completed replies; streaming chat and approval answers remain separate.

Verification: generated experimental schema from the installed CLI matches request/response fields. A live read-only thread/queue/list call against an actual desktop-observed thread succeeded without sending input, resuming it or reading queue bodies into logs. Parameter tests cover the exact UUID, unchanged multiline/unicode text, bounded inputs, unsupported identities, acknowledgement correlation and duplicate/uncertain-submit latching. No test message was sent to an existing user conversation, so real send → consumption → desktop/UI convergence remains unverified.

## Compact completion notice — 2026-10-27

Observed Codex completion timestamps now drive a small top-attached 320×52 notice while the island is hidden. It dismisses after five seconds; clicking selects that exact session in Agents and reveals its detail. Startup history, repeated polling, retained files and an older completion returning after disappearance cannot replay the same notice. Multiple new completions in one scan collapse to the newest notice. Open pages, typing, dragging, pending questions and fullscreen restrictions take precedence. Working/unknown/aborted records never generate a finished notice. The session itself still remains in the list for the separately configured 30-minute retention.

Twenty-one scoped reducer, deduplication and surface tests passed, including completion timeout and non-interruption of input/open routes. The observer still polls every three seconds, so completion detection is not instantaneous. End-to-end visual timing with an actual newly completed agent turn remains unverified.

## Local Codex hook bridge — 2026-10-27

The user explicitly authorized adding a local hook. The packaged native IslandHook helper uses a private 0700 mailbox with 0600 bounded files, UUID request directories, same-user regular-file and no-symlink checks, helper PID/birth/executable/ancestor checks, immutable request comparison, and a 120-second deadline. The app revalidates before any response. An unavailable app, malformed input, expired helper or timeout returns an empty hook result so the original Codex approval/question flow proceeds. No automatic allowance, permanent policy, trust bypass, model/config override or chat-queue substitute is used. Explicit PermissionRequest choices are allow once, deny, or defer to Codex. Existing user hooks remain in control too; another hook's deny is not overridden.

For supported local Codex PreToolUse calls to request_user_input/request_user_input_async, the island previews the question and options, then hands off to the original Codex tool UI. PreToolUse cannot supply that tool's return value, so no answer is invented. Secret questions are excluded. Native daemon questions now support up to three grouped non-secret questions with complete, exact answer validation. A pending prompt remains visible until explicit dismissal or resolution instead of following the short hover-close delay.

The installer merges only IslandMac entries into ~/.codex/hooks.json, backs up exact existing bytes when changing it, preserves unrelated fields/handlers, refuses malformed/symlink targets, detects concurrent config edits, and refreshes its native helper atomically. It does not edit Codex hook trust records or enable bypass flags. New hooks require user review/trust via Codex CLI /hooks. User/project command hooks are not supported by all cloud-orchestrated Work workflows; installing a local hook is not evidence of cloud event delivery.

Verification: all 127 Swift tests passed (optional live/capture checks retain their opt-in skips); two isolated installer tests passed. The installed CLI reports hooks stable and enabled. Installer readback found exactly one IslandMac PermissionRequest and one matching PreToolUse handler. Real trusted Codex lifecycle delivery and human permission response still require live verification after trust review.

Runtime bridge confirmation: a clearly labeled TEST fixture invoked the packaged native helper with no executable command. The island visibly rendered the simulated request and its three choices. A fresh AX snapshot was checked for the SIMULATION ONLY marker before pressing Deny; the helper returned the exact deny hook result and the fixture exited successfully. This verifies helper → mailbox → native prompt → selected response → helper, not Codex trust or actual lifecycle execution. A preceding simulation did not confirm its requested deny outcome and is not counted as a pass. Mailbox publication now uses complete temporary files and an exclusive hard-link publication so readers cannot consume partially written requests/responses; six scoped mailbox/identity/drag regressions passed after that change. The app was normally restarted with the final build and the installed helper refreshed idempotently.


## Shared-daemon question response verified — 2026-10-29

A disposable read-only Codex CLI 0.164.0 session connected using `codex --remote unix://` to the already-running managed app-server 0.165.0. In Plan mode it requested one non-secret question with selectable choices and free text. The optional trusted PreToolUse hook first displayed a preview in IslandMac; clicking Answer in Codex released that hook without supplying an answer. The actual daemon request then appeared in IslandMac with two choices, a Reply text field, and Send.

A fresh AX snapshot confirmed the exact test question before entering `ISLAND_TEXT_OK` in the island text field. Send became enabled; clicking it cleared the pending prompt. The original CLI left its question UI and subsequently printed `ISLAND_TEXT_OK`. This verifies a real model-issued request → island input → protocol response → original CLI result for one controlled single-question case, rather than a fixture or chat-queue acknowledgement. The completed test CLI was disconnected normally. No files were changed by that test session.

This does not establish delivery for private-stdio desktop questions, asynchronous desktop questions, grouped questions, secret input, permissions, or reconnect/stale-request races. The hook preview still adds an extra handoff step before the daemon question. Starting a separate daemon alone does not attach it to a running desktop server.
