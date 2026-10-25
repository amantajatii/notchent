# Phase 2 Task 3 implementation report

Status: DONE_WITH_CONCERNS (native Finder acceptance and restart are pending).

## Implemented

- `FileShelf` actor persists an atomic JSON manifest and app-owned regular-file copies under Application Support/IslandMac/FileShelf. Original references use persistent URL bookmarks. Each item has a UUID, original display name, storage mode, path/bookmark, and refreshed availability. Directory and symlink imports are rejected; file copying uses FileManager streaming rather than loading contents into memory.
- Import batches publish the manifest only after every file has been copied/bookmarked; copied files are rolled back on import failure. Removal persists the manifest first, deletes only an app-owned copy, and never deletes the original. Only `.confirmed` delivery removes an item.
- Normal Files route has native Quick Look thumbnail/icon fallback, filename with full-name help, selection, remove, and a drag source. Home shows a file count. Drop mode contains only its drop target and no thumbnails or navigation.
- An NSDraggingDestination accepts file URLs. A narrow top drag trigger is detected through the drag pasteboard plus pressed mouse state and a change count since idle, even while the panel is hidden; it dispatches `.dragChanged` to the existing reducer. The destination imports in the selected copy/reference mode. No invisible trigger window was added.
- Drag-out uses NSFilePromiseProvider. The app writes the promised destination and compares source and destination in bounded 256 KiB chunks before reporting `.confirmed` and removing the shelf item. Empty/rejected/canceled drag sessions never remove it. This is producer-side destination verification; live Finder acceptance is still untested.
- Added English/Indonesian file empty, unavailable, remove, and count labels in the existing String Catalog. File names are never translated.

## Interfaces for following tasks

- `IslandCore`: `ShelfItem: Codable, Identifiable, Sendable, Equatable`; `FileShelf(root:) throws`, `items() -> [ShelfItem]`, `url(for:) throws -> URL?`, `importFiles(_:mode:) async throws -> [ShelfItem]`, `remove(_:) async throws`, `completeDelivery(_:receipt:) async throws`.
- `IslandMac`: `IslandShell.files: NativeFileAccess`; `.featureViews[.files]` and `.fileSummaryView` are installed at launch. File import reads `shell.settings.fileStorage`. `FileDropHostingView` owns native ingress. No terminal/agent integration surface was changed.

## Verification

- RED: `scripts/test.sh --filter FileShelfTests` exited 1 before implementation with `cannot find 'FileShelf' in scope`; this was expected. This wrapper is the CLT-compatible form of the requested `swift test --filter`.
- GREEN: same focused command exited 0, five tests passed. Tests use isolated filesystem directories and cover duplicate names/UUIDs, copy survival after source deletion and relaunch, missing reference, original retention on removal, an interrupted sidecar manifest write, and canceled/failed/unconfirmed delivery retaining the owned copy.
- Final `scripts/test.sh` exited 0: 37 tests in 10 suites passed; one opt-in Spotify live test skipped. `scripts/build-app.sh` exited 0 and signed `.build/apps/IslandMac.app`. `git diff --check` clean.
- Terminated only the repository app PID 45337 and opened the rebuilt bundle normally, without `--show`. New PID 47783 was confirmed at the expected executable path. No file UI or Finder interaction was observed by this worker.

## Pending native acceptance and limits

- Finder import, drag cancellation, successful Finder promised-file handoff, unavailable reference UI, duplicate-name UI, and quit/relaunch UI were not exercised live. The tests verify storage semantics but cannot prove native drag routing, Finder acknowledgement, or visual layout. Root owns these checks.
- A Mac restart was not performed; a user-chosen restart time is required. Persistence is verified with a new actor instance in tests, not an actual restart.
- Security-scoped access is started where the native service reads imported/dragged references and Quick Look thumbnails. Current local app is unsandboxed; behavior after future sandboxing is not verified.

## Self-review

Checked that unknown receipts retain the copy; only a verified promised destination triggers removal. The drag trigger compares pasteboard change count with idle to avoid showing Drop on an ordinary click after an old file drag. No original path is deleted, no whole-file byte load or unbounded directory traversal was introduced. The report does not claim the pending native checks.

## Round 1 review fixes (after `ae30e37`)

- Replaced the immediate post-write `.confirmed` call with a per-attempt `DeliveryGate`. Confirmation now requires both a successful independent destination byte comparison and a final native `.copy` drag operation. Cancellation and failed writes are terminal, including when a promise callback finishes later. The provider carries its attempt identity so delayed callbacks cannot act on a newer drag. Copy/compare now runs off the MainActor; the native completion callback receives cancellation if a drag was canceled during a pending write.
- Validated owned deletion paths before changing the manifest. The sole accepted form is `Files/<item UUID>` under the shelf root; symlinked root, Files directory, or target are rejected. The same validation runs before import copying, so a symlinked Files directory cannot redirect a new copy outside the shelf. `completeDelivery(.confirmed)` uses the same guarded removal.
- Registered each copy target for rollback before invoking FileManager copy. A partial copy that throws is now removed, and the manifest/in-memory items remain unchanged.
- Replaced the old unrelated `.tmp` test with an injected failed manifest replacement that leaves the previous on-disk manifest and actor state intact. Added an injected partial-copy failure and forged traversal/symlink deletion tests.
- `NSDraggingDestination.performDragOperation` must return synchronously; the shelf import remains asynchronous. Its `true` value means the native destination accepted file URLs, not that persistence succeeded. Failure is now shown in both Files and Home summary. No Finder delivery result is claimed.

### Round 1 TDD and verification

- RED: `scripts/test.sh --filter 'FileShelfTests|DeliveryReceiptTests'` exited 1 before the fix with missing `DeliveryGate`, missing `FileShelfOperations`, and unsupported injected initializer. This represented the missing ordering and failure-injection behavior.
- GREEN: same focused command exited 0 with 17 tests in 2 suites passed. New cases cover write-before-cancel, cancel-before-write, accepted-before-write, write-before-accepted, failed write, failed partial copy, failed manifest replacement and actor rollback, forged traversal path, and symlinked Files directory.
- Final `scripts/test.sh` exited 0: 45 tests in 10 suites passed; the opt-in Spotify live test remains skipped. `scripts/build-app.sh` exited 0, signed bundle generated. `git diff --check` clean. Existing SwiftPM native-build-system deprecation warning remains.
- Did not relaunch the app or repeat live UI/Finder checks during this review fix. The previously launched normal-mode process may still run the prior bundle until root restarts it. Mac restart remains pending at a user-chosen time.

Self-review: the confirmed transition is issued once per attempt, only after both signals; a canceled attempt stays retained even when its write task returns. Unsafe decoded paths throw before manifest mutation. The injected failure tests exercise actual copy/write interruption points rather than unrelated sidecar files. Native Finder callback ordering and destination behavior remain unverified live.
