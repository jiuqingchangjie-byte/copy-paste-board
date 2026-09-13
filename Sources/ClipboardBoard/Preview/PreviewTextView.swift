import ClipboardCore
import AppKit

/// Read-only text with normal selection and a single explicit copy command.
final class PreviewTextView: NSTextView {
    var onCopyText: ((String) -> Bool)?

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
        _ = onCopyText?((string as NSString).substring(with: range))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copy = menu.addItem(withTitle: L10n.tr("复制选中文本"), action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        let select = menu.addItem(withTitle: L10n.tr("全选"), action: #selector(selectAll(_:)), keyEquivalent: "")
        select.target = self
        return menu
    }
}
