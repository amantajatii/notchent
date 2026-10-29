# Notchent

**Notch for Agent.**

A native Mac notch companion for monitoring coding agents, receiving notifications, and continuing supported conversations.

Notchent is a native menu bar app with Home, Spotify, Files, and an integrated terminal. Requires macOS 14 or later. **The MVP is incomplete:** agent support and live validation vary by integration, as detailed below. See the [acceptance record](docs/validation/mvp-acceptance.md) for validation evidence.

## Build and launch

From the repository root, with Apple Command Line Tools active:

```sh
scripts/test.sh
scripts/build-app.sh
open .build/apps/Notchent.app
```

The product name is **Notchent**. The Swift target `IslandMac`, bundle ID, and existing storage paths are retained for compatibility with existing integrations and user data.

Build output: `.build/apps/Notchent.app` (debug, ad-hoc signed, bundle ID `dev.nativeisland.app`). The app has not been notarized or validated for external distribution. Builds use the host architecture; the local baseline is arm64, macOS 27.0.1, and Swift 6.4. SwiftTerm is pinned to exactly `1.99.1` through `Package.resolved`; a compiler that supports its manifest (Swift tools 6.2+) is required.

With the local CLT 6.4 setup, plain `swift test` cannot find the testing framework. `scripts/test.sh` uses Swift Testing, `--disable-xctest`, the CLT framework search path/rpath, and the native build engine. The native engine deprecation warning remains; it has not been migrated or suppressed.

To upgrade, choose **Quit** in the old instance first, complete any confirmation for app-owned sessions, then build and run the `open` command above. Opening a bundle while its app is already running does not reload the new binary. Building also does not restart the app. During normal use, the panel hides when idle; hover over the top center of the screen to open it. Avoid `--show` for normal use: that inspection mode keeps the panel open.

## Usage and permissions

Home prioritizes Music/Spotify, with summaries for Agents and Files. Settings stores Language (English by default, or Bahasa Indonesia), Open delay, Close delay, Full screen, and File storage. Terminal text, filenames, and agent request contents are not translated.

Open Spotify yourself, then use **Connect Spotify** when you want to grant Automation permission. macOS may ask for approval; you control access through the dialog or System Settings → Privacy & Security → Automation. Polling does not silently request permission or launch Spotify or music playback. Consent, denied, and unavailable states are distinct. Metadata, artwork, and playback controls have not been verified live on the latest bundle. Opening the panel does not require Accessibility or Screen Recording permission; additional permissions do not enable unimplemented agent response features.

Files accepts regular files; directories and symlinks are rejected. **Copy** stores an app-owned copy in `~/Library/Application Support/IslandMac/FileShelf`; **Reference** stores a bookmark to the original and may become unavailable if the source disappears or cannot be accessed. No application storage quota is promised; disk space and permissions still limit imports. Do not treat the shelf as a backup.

Dragging files in displays the drop area. AppKit accepts the drop before the asynchronous import completes; check the item or error message before assuming the file was saved. Dragging out uses file promises: removing a shelf item requires a native `.copy` result and a successful byte comparison with the destination. Canceled, failed, or uncertain deliveries retain the item. **Remove** deletes only the app-owned copy or reference, never the original file. This is verification on the producer side, not proof that every destination app has consumed the file. Finder dragging and behavior after restarting the Mac still require live testing.

For Terminal, choose a folder to create a shell session. **Hide** hides the panel while preserving the PTY and draft; switching tabs preserves them too. **Close** requests asynchronous termination of that app-owned session. **Quit** asks for confirmation when app-owned sessions are running and waits for termination; external sessions are outside the store. Confirmation and focus behavior have not been verified live on the latest build. Avoid quitting just to test if you have terminal work to preserve.

## Current agent support

| CLI | Executable detected | Discovery | Read questions / send answers |
| --- | --- | --- | --- |
| Codex CLI | `codex` | Candidate metadata | A single question with a text answer through the local daemon was verified in one controlled test; command approvals and other combinations remain unverified |
| Claude Code | `claude` | Candidate metadata | Not implemented |
| Antigravity CLI | `agy` | Candidate metadata | Not implemented |
| Oh My Pi | `omp` | Candidate metadata | Not implemented |

All entries share these limits: descendants of internal shells are mapped to app-owned terminals using PID and process birth time. Interpreter wrappers may be missed. External VS Code, Orca, Terminal, and iTerm2 hosts are recognized through process ancestry. Codex desktop sessions are read through rollout files currently open by the process (metadata, activity, and completion summaries; read-only), without scanning history or changing hooks/configuration. Stable pane/project identity is not known, so external pane mapping and Open origin are unavailable. The Codex adapter uses daemon thread identity rather than Terminal pane identity. One Codex CLI session through a shared daemon has demonstrated live questions and text answers; this does not validate all 16 CLI/host combinations. Historical version inventory is in [agent capabilities](docs/validation/agent-capabilities.md), not a compatibility guarantee.

The Codex adapter connects to the public WebSocket endpoint of an already running local daemon, displays requests with thread/project names, and sends answers only after a user click. It preserves all command approval decisions offered by this protocol version, in their original order: run once, allow for the session, command prefix rules, network host rules, denial, or cancellation. Session/rule options appear only when Codex supplies them, with their scope shown on the button. Single non-secret questions and batches of up to three questions are supported; file-change/permissions requests and MCP elicitation are not supported through the daemon adapter.

Protocol framing/routing and native initialize/loaded-list connections have been tested. Command approval replay and its panel presentation have been observed for Codex/Terminal. One controlled test verified sending a text answer through the notch UI and receiving the same value in the CLI; command approval responses have not been verified live. A sent status does not confirm receipt. A resolved event from the server removes the prompt, including when answered at its origin. Activity status on process cards remains unknown.

Basic discovery does not install hooks/plugins or modify CLI/shell configuration. Local desktop popups can use optional hooks installed only with user permission. If the user selects a persistent rule option, Codex may save the rule through its own mechanisms; the app never chooses that option automatically.

The adapter observes loaded, active threads through the user's existing daemon without requiring a Codex process with a TTY. Verified daemon sessions appear as separate cards from process candidates. Subscriptions use thread/resume without configuration overrides, check loaded state before and after, and detach when idle or exiting. The protocol does not provide an atomic join against unload; that race has not been verified safe live. Resume also changes daemon client attribution and may keep a monitored thread loaded longer. This subscription path does not read conversation history or terminal output.

In Agents, select a Codex session and use the chat field to continue the same conversation. Enter or the arrow button queues text through thread/queue/add using that session's UUID; it does not create or resume a conversation on another server. Queued means the queue accepted the message, not that a reply is complete. Text and pasted-image drafts are kept per session while the app is running. Paste an image with **⌘V** in the composer; review its preview or remove it before sending. Images can be sent with or without text. Attachments must fit within the 4 MB protocol message limit after encoding; oversized images are rejected with the draft preserved. The send button turns white when a valid message is ready and the connection is available. Confirmed queued messages stay in the chat history until matched with their server history entry by client message ID. History refreshes after queue confirmation and observed completion changes. If delivery is uncertain, check the original conversation before reopening the draft to send it again. Completed replies follow local summary monitoring; streaming and desktop approval responses are unavailable. Delivery through to actual processing by Codex has not been verified end to end.

### Optional local Codex hooks

Local Codex question hooks are supported. `scripts/build-app.sh` also bundles the native IslandHook helper. The installer below adds PermissionRequest and question-specific PreToolUse handlers to `~/.codex/hooks.json`, saves a backup, and preserves other handlers:

```sh
python3 scripts/install-codex-hook.py --helper .build/apps/Notchent.app/Contents/MacOS/IslandHook
```

After installation, review and trust the IslandMac definitions through `/hooks` in Codex CLI. The installer does not modify trust records or security mode. Permission prompts offer allow once, deny, or continue in Codex. Desktop preferences are previewed and handed off to the original UI; PreToolUse cannot return tool answers. Cloud-orchestrated Work does not support all of these local hooks.

### File drag activation

The drop area opens when a file drag starts anywhere on screen, without requiring a hover at the top edge. It stays open during the drag and closes after the file is released or the drag is canceled. Stale file data on the drag pasteboard and text drags do not open the panel.

### Answering Codex questions through the notch

Run the CLI session on the same daemon as Notchent:

```sh
codex app-server daemon start
codex --remote unix://
```

When Codex asks a question, answer in the notch prompt panel. If the optional hook shows **Answer in Codex** first, press it to skip the preview; the official daemon question then provides choices or a text field and **Send** in the panel. A controlled test on 2026-10-29 verified that `ISLAND_TEXT_OK` was sent from the panel and received by the CLI. This does not connect desktop session dialogs that use a separate stdio server.
