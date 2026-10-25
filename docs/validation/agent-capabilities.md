# Agent capability probe — 2026-10-25

Task 1 establishes a safe inventory and identity foundation. **No agent/host combination is verified for prompt extraction or response routing.** The no-CLI-setup feasibility gate remains open. No hooks, plugins, global installations, credentials, environment, private session databases, or raw transcripts were accessed.

## Reproduce

- `scripts/test.sh --filter SessionIdentityTests` (focused) or `scripts/test.sh` (full suite).
- `scripts/build-app.sh --probe`
- `open .build/apps/IslandProbe.app --args inventory`
- `.build/apps/IslandProbe.app/Contents/MacOS/IslandProbe inventory` for JSON stdout.
- `IslandProbe agent --pid <positive PID>` inspects only one explicitly selected controlled process's birth time. It does not infer an owner/pane or accept arbitrary response text.
- `panel`, `drag`, and `spotify` dispatch to explicit unsupported observations.

Swift 6.4 CLT uses swiftbuild by default, which failed to find XCTest. XCTest was also absent in native mode. Bundled Swift Testing works with native mode, `--disable-xctest`, and explicit developer framework search/rpath flags; `scripts/test.sh` applies these locally using `xcode-select -p`. No toolchain changes. Native engine emits its documented deprecation warning. Minimum macOS 14 matches the plan and bundled Testing.

## Observed inventory

| Component | Exact version | Scope |
| --- | --- | --- |
| Codex CLI | 0.164.0 | `codex --version`; installed executable only |
| Claude Code | 2.1.258 | `claude --version`; installed executable only |
| Antigravity CLI | unavailable on current PATH | `command -v antigravity`; app installation is not CLI proof |
| Oh My Pi | unavailable on current PATH | `command -v pi`; alternate names/locations unverified |
| VS Code | 1.143.1 | `/Applications/Visual Studio Code.app` Info.plist |
| Orca | 1.4.238 | `/Applications/Orca.app` Info.plist; bundle ID `com.stablyai.orca` |
| Terminal | 2.15 | `/System/Applications/Utilities/Terminal.app` Info.plist |
| iTerm2 | 3.7.3 | `~/Applications/iTerm.app` Info.plist |

The executable inventory observed `AXIsProcessTrusted() == true` for this execution context. It did not request permission. No matching running host was returned by `NSWorkspace.shared.runningApplications` in that execution context; no AX attribute values or terminal text were read. This is not proof those applications are closed in another GUI context. Application-level AX attribute-name enumeration is implemented for matching running hosts, but that branch was not exercised. Bundle open returned exit 0; LaunchServices execution output and bundle-specific permissions were not observed. The bundle is a short-lived LSUIElement executable, with stdout JSON, no visible window.

Selected controlled shell metadata probe observed a process birth time through `proc_pidinfo`; no agent session selected. Session IDs combine owner instance, PID, microsecond process birth time, and terminal pane/session key. Unknown owner or missing key resolves to nil. Caller-supplied identity components are not discovery evidence or permission to send; this probe offers no send operation.

## Capability matrix

D = session discovery, R = prompt extraction, S = response routing, O = open origin. `untested` is evidence status, not a successful boolean. Installed host/version applies to each row. Missing CLI means unavailable under the PATH check only.

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
| Antigravity CLI unavailable | VS Code 1.143.1 | unavailable | untested | untested | untested | PATH only |
| Antigravity CLI unavailable | Orca 1.4.238 | unavailable | untested | untested | untested | PATH only |
| Antigravity CLI unavailable | Terminal 2.15 | unavailable | untested | untested | untested | PATH only |
| Antigravity CLI unavailable | iTerm2 3.7.3 | unavailable | untested | untested | untested | PATH only |
| Oh My Pi unavailable | VS Code 1.143.1 | unavailable | untested | untested | untested | PATH only |
| Oh My Pi unavailable | Orca 1.4.238 | unavailable | untested | untested | untested | PATH only |
| Oh My Pi unavailable | Terminal 2.15 | unavailable | untested | untested | untested | PATH only |
| Oh My Pi unavailable | iTerm2 3.7.3 | unavailable | untested | untested | untested | PATH only |

Runtime outcomes use observed / unsupported / unavailable / denied. Unexercised checks use unavailable with explicit unverified evidence when emitted; unsupported means this probe lacks the adapter, not that the host can never support it. `AgentCapabilities` flags default false and must not be interpreted as test outcomes; observations carry evidence.

## Public surface research

- [VS Code API](https://code.visualstudio.com/api/references/vscode-api) exposes terminal objects and sendText inside extensions. This is not evidence of an external native macOS interface; installing an extension would violate this phase's setup constraint.
- [VS Code shell integration](https://code.visualstudio.com/docs/terminal/shell-integration) documents shell state integration; no installation/configuration was performed.
- [iTerm2 session API](https://iterm2.com/python-api/session.html) documents session IDs and session operations. API enablement, identity mapping, and authorization were not exercised.
- [Apple Terminal automation](https://support.apple.com/en-kw/guide/terminal/trml1003/mac) documents AppleScript automation. Automation permission and stable pane mapping remain untested.
- [Orca terminal documentation](https://www.onorca.dev/docs/terminal) describes panes and agent state. A documented supported external prompt/response interface was not established. Several unrelated products share the name Orca; their REST APIs are not evidence for `com.stablyai.orca`.

## Remaining controlled live checks

Duplicate sessions, background tabs, resolved/expired prompts, permission revocation, and a response to an explicitly approved harmless prompt are all **untested**. No foreground success is claimed, so no background capability is inferred. A later controlled GUI run must verify owner and terminal session key, revalidate process birth time before action, and reject stale/expired prompt routes. Do not answer any live agent permission request automatically. No production integration recommendation can yet be made from this inventory.
