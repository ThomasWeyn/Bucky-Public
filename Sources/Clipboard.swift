import AppKit

/// Temporary, in-memory snapshots only. Never polls or persists clipboard data.
final class ClipboardDelivery {
    let pasteboard: NSPasteboard
    let maxBytes: Int
    private var pending: (items: [[NSPasteboard.PasteboardType: Data]], count: Int)?
    private var restoreTask: DispatchWorkItem?
    var restorationPending: Bool { pending != nil }
    init(pasteboard: NSPasteboard = .general, maxBytes: Int = 16 * 1024 * 1024) {
        self.pasteboard = pasteboard; self.maxBytes = maxBytes
    }
    private func snapshot() -> [[NSPasteboard.PasteboardType: Data]]? {
        let items = pasteboard.pasteboardItems ?? []
        guard items.count <= 128 else { return nil }
        var result: [[NSPasteboard.PasteboardType: Data]] = [], bytes = 0
        for item in items {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    // AppKit advertises this derived encoding for some rich-text
                    // items without supplying bytes. The available UTF-8 string
                    // already preserves the text and can supply this conversion.
                    if type.rawValue == "public.utf16-external-plain-text", item.data(forType: .string) != nil { continue }
                    return nil
                }
                bytes += data.count
                guard bytes <= maxBytes else { return nil }
                values[type] = data
            }
            guard !values.isEmpty else { return nil }
            result.append(values)
        }
        return result
    }
    @discardableResult func copy(_ text: String) -> Bool {
        cancelRestore()
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    @discardableResult func stagePaste(_ text: String, preserve: Bool) -> Bool {
        let before = pasteboard.changeCount
        let original = pending?.count == before ? pending?.items : (preserve ? snapshot() : nil)
        // A clipboard owner may change while materializing a lazy representation.
        guard before == pasteboard.changeCount else { cancelRestore(); return false }
        cancelRestore()
        pasteboard.clearContents()
        let wrote = pasteboard.setString(text, forType: .string)
        if preserve, let original { pending = (original, pasteboard.changeCount) }
        if !wrote { restorePending() }
        return wrote
    }
    func scheduleRestore(after seconds: TimeInterval) {
        guard pending != nil else { return }
        restoreTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.restorePending() }
        restoreTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }
    @discardableResult func restorePending() -> Bool {
        guard let saved = pending else { return false }
        cancelRestore()
        let items = saved.items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        guard pasteboard.changeCount == saved.count else { return false }
        pasteboard.clearContents()
        return items.isEmpty || pasteboard.writeObjects(items)
    }
    private func cancelRestore() { restoreTask?.cancel(); restoreTask = nil; pending = nil }
    static func holdDuration(for bundleID: String?) -> TimeInterval {
        guard let id = bundleID?.lowercased() else { return 1.5 }
        if ["remote", "rdc", "citrix", "anydesk", "teamviewer", "horizon", "vnc"].contains(where: id.contains) { return 5 }
        if ["com.microsoft.word", "com.microsoft.outlook"].contains(id) { return 3 }
        return 1.5
    }
}
