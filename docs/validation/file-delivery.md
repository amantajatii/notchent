# File delivery feasibility — 2026-10-25

## Observed implementation and unit evidence

`DeliveryReceipt` permits removal only for `.confirmed`. Four Swift Testing checks pass; cancelled, failed and unconfirmed retain the copy. Native path drag never produces confirmed: AppKit's ended operation reports an operation, not an application-level receipt or assurance that a consumer has finished reading the source. Empty operation cannot reliably distinguish Escape from rejection.

Run `scripts/build-app.sh --probe`, then `open -n .build/apps/IslandProbe.app --args drag`.
The probe creates an owned temporary folder and harmless text sample; it does not delete its files. Choose **Open owned Finder target**, drag the first sample into that folder, then **Compare copied bytes**. Compare checks actual destination bytes against retained source. Escape while dragging exercises cancellation; dropping on the instruction label exercises a nonaccepting target. Neither is reported as confirmed.

The second sample uses `NSFilePromiseProvider`. Its write callback writes independent harmless bytes to the consumer-supplied destination, reads back and compares them, then invokes the completion handler. That is a stronger boundary for app-owned destination writing than path-drag end, but no general consumer receipt is inferred. All copies remain retained. Write errors are reported separately. Success must also be exercised against actual Finder before elevating the gate.

## Live acceptance matrix

| Scenario | Status | Evidence required |
| --- | --- | --- |
| Finder path copy | Untested; UI control unavailable in parent session | Native callback plus matching destination bytes |
| Escape cancellation | Untested | Empty operation and source still readable |
| Rejecting target | Untested | Rejection and retained source |
| Finder promised copy | Untested | Provider write callback, byte match, Finder-visible copy |
| Destination write failure | Untested | Provider error and retained source |

Compilation/unit success is not live delivery proof. Gate: **NO-GO for automatic last-copy removal or strict one-transfer semantics**. Product decision needed before proceeding: retain a shelf copy until explicit removal, or adopt a separately validated promised-file delivery boundary. No one-transfer behavior is changed here. Probe files intentionally remain in the temporary folder for inspection.
