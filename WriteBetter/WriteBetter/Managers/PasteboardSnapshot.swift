import AppKit

/// A full copy of a pasteboard — every item, every type — so borrowing the
/// clipboard never destroys images, files or rich text.
struct PasteboardSnapshot {
    private let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    /// Marker honoured by clipboard managers (nspasteboard.org): "don't record this".
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    /// Replaces the pasteboard's contents with this snapshot.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.filter { !$0.isEmpty }.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }

    /// Restores only if nobody has written since `changeCount` — never clobbers a
    /// newer user copy. Returns whether it restored.
    @discardableResult
    func restore(to pasteboard: NSPasteboard, ifChangeCountIs changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        restore(to: pasteboard)
        return true
    }

    /// Writes `text` marked transient, and returns the resulting `changeCount`.
    @discardableResult
    static func writeTransient(_ text: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        return pasteboard.changeCount
    }
}

#if DEBUG
/// Wire into `WriteBetterSelfCheck.runAll()`: `PasteboardSnapshotCheck.run()` returns failure messages.
enum PasteboardSnapshotCheck {
    @MainActor static func run() -> [String] {
        var failures: [String] = []
        let pb = NSPasteboard(name: NSPasteboard.Name("wb.selfcheck.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }

        // Multi-type / multi-item content survives a borrow + restore.
        pb.clearContents()
        let a = NSPasteboardItem()
        a.setString("hello", forType: .string)
        a.setData(Data([1, 2, 3]), forType: .png)
        let b = NSPasteboardItem()
        b.setString("world", forType: .string)
        pb.writeObjects([a, b])
        let snap = PasteboardSnapshot(pb)
        let count = PasteboardSnapshot.writeTransient("temp", to: pb)
        if pb.data(forType: PasteboardSnapshot.transientType) == nil { failures.append("transient marker missing") }
        if !snap.restore(to: pb, ifChangeCountIs: count) { failures.append("restore refused despite matching changeCount") }
        let items = pb.pasteboardItems ?? []
        if items.count != 2 { failures.append("item count \(items.count) != 2") }
        if items.first?.data(forType: .png) != Data([1, 2, 3]) { failures.append("png lost") }
        if items.first?.string(forType: .string) != "hello" { failures.append("string lost") }

        // A newer write must not be overwritten.
        let c2 = PasteboardSnapshot.writeTransient("temp2", to: pb)
        pb.clearContents(); pb.setString("user copy", forType: .string)
        if snap.restore(to: pb, ifChangeCountIs: c2) { failures.append("restore clobbered newer copy") }
        if pb.string(forType: .string) != "user copy" { failures.append("newer copy changed") }
        return failures
    }
}
#endif
