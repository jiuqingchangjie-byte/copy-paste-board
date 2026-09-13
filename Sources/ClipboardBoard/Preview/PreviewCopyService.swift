import ClipboardCore

/// The sole preview write path: an explicit copy, never opening or zooming.
/// Monitor.write suppresses a second automatic capture of the same action.
final class PreviewCopyService {
    private let monitor: PasteboardMonitor
    var onCopied: ((HistoryEntry) -> Void)?

    init(monitor: PasteboardMonitor) { self.monitor = monitor }

    @discardableResult
    func copy(_ text: String) -> Bool {
        copy(.text(text), sourceName: L10n.tr("剪贴板预览"))
    }

    @discardableResult
    func copy(_ payload: ClipPayload, sourceName: String) -> Bool {
        guard payload.isValid, payload.byteCount <= 8 * 1024 * 1024 else { return false }
        monitor.poll()
        guard monitor.write(payload) else { return false }
        onCopied?(HistoryEntry(payload: payload, sourceName: sourceName))
        return true
    }
}
