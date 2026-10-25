# Spotify feasibility — 2026-10-25

Installed version: **1.3.6.1921**, read from Spotify.app Info.plist. The installed `Contents/Resources/Spotify.sdef` exposes player state (stopped/playing/paused), current-track name/artist, artwork URL, and play/pause/next/previous commands. The binary artwork property is deprecated and documented as never set. Dictionary support is not evidence of successful live controls.

`IslandProbe spotify --observe` performs read-only observation; `spotify` opens an explicit control window. App availability, playback, metadata, artwork URL and controls are recorded separately. Preflight uses `AEDeterminePermissionToAutomateTarget(..., false)`; it never requests a prompt or grants permission. Checks stop when Spotify is not already running. The reusable `SpotifyEventClient` captures a running PID and launch date, validates that identity before and after each event, and sends only PID-addressed native Apple Events. A process disappearing between validation and dispatch returns unavailable; no bundle/name target or launch fallback exists. No automatic play, launch, pause or track change is performed.

Observed native run from the built CLI: Spotify **running**, Automation **requires-consent (-1744)**, state/metadata/artwork **untested**. Requires-consent is distinct from denied (-1743). No audio or app state was changed. Permission identity may differ between direct executable and bundled GUI; bundled access is untested.

| Check | Live result |
| --- | --- |
| Running app discovery | Observed |
| Not-running handling | Implemented guard; live scenario untested (Spotify not quit automatically) |
| Paused / playing / stopped | Untested; requires consent |
| Metadata | Untested; requires consent |
| Artwork URL | Untested; requires consent |
| Artwork image fetch/decode | Untested; probe does not fetch |
| Denied Automation | Explicit -1743 branch implemented; revocation not performed |
| Playback controls | Explicit buttons implemented; live untested |

Manual validation: open the bundled `spotify` scene, deliberately authorize via macOS as applicable, refresh for paused and playing states chosen by the user, then click each desired control and observe actual audio/track state. Capture revoked/denied independently. Phase 2 should offer an explicit Connect/Allow action; background polling must not request access silently.

Gate: **conditional GO for implementation behind permission/unavailable states; NO-GO for claims of verified live playback, metadata or artwork integration** until manual consent and UI checks complete.
