import AppKit
import ClipboardCore

/// Controls transient lifetime separately from detached image windows.
/// No clipboard or paste-service access: all writes require the copy callback.
final class HistoryPreviewCoordinator {
    let hover = HoverPreviewScheduler()
    private(set) var transient: EntryPreviewWindowController?
    private(set) var detached: [EntryPreviewWindowController] = []
    var onCopyText: ((String) -> Bool)?
    var onRestoreSelection: (() -> Void)?
    var onFamilyResignKey: (() -> Void)?
    var isPreviewing: Bool { transient != nil }

    func contains(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return transient?.window === window || detached.contains { $0.window === window }
    }

    func show(entry: HistoryEntry, anchor: NSRect, parent: NSWindow, takeFocus: Bool) {
        hover.cancel()
        if let current = transient, current.entryID == entry.id {
            if takeFocus { current.window?.makeKey(); current.focusContent() }
            return
        }
        closeTransient(restoreSelection: false)
        guard let controller = EntryPreviewWindowController(entry: entry, onCopyText: { [weak self] in
            self?.onCopyText?($0) == true
        }) else { return }
        transient = controller // Establish family membership before AppKit changes focus.
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            if self.transient === controller { self.closeTransient(restoreSelection: true) }
            else {
                controller.hide()
                self.detached.removeAll { $0 === controller }
                self.onRestoreSelection?()
            }
        }
        controller.onPinChanged = { [weak self, weak controller] pinned in
            guard let self, let controller, pinned, self.transient === controller else { return }
            self.transient = nil
            self.detached.append(controller)
            self.onRestoreSelection?()
        }
        controller.onResignKey = { [weak self] in self?.onFamilyResignKey?() }
        controller.present(relativeTo: anchor, parent: parent, takeFocus: takeFocus)
    }

    func closeTransient(restoreSelection: Bool) {
        hover.cancel()
        let current = transient
        transient = nil
        current?.hide()
        if current != nil, restoreSelection { onRestoreSelection?() }
    }

    func reconcile(entries: [HistoryEntry]) {
        hover.cancel()
        if let transient, !entries.contains(where: { $0.id == transient.entryID }) {
            closeTransient(restoreSelection: true)
        }
        // Pinned images are independent snapshots, not extra history records.
    }

    func closeAll() {
        closeTransient(restoreSelection: false)
        detached.forEach { $0.hide() }
        detached.removeAll()
    }

    deinit {
        transient?.hide()
        detached.forEach { $0.hide() }
    }
}
