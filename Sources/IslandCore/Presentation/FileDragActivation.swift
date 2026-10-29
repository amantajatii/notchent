/// The drag pasteboard must change during a held mouse button; stale file data is not a drag.
public struct FileDragActivation {
    private var idleChangeCount: Int
    public init(idleChangeCount: Int) { self.idleChangeCount = idleChangeCount }
    public mutating func update(mouseDown: Bool, hasFileURLs: Bool, changeCount: Int) -> Bool {
        if !mouseDown { idleChangeCount = changeCount; return false }
        return hasFileURLs && changeCount != idleChangeCount
    }
}
