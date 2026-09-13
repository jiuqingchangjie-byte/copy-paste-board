import AppKit
import ClipboardCore

/// A focused editor: validate first, persist through the app, then apply.
final class PreviewPreferencesController {
    func edit(current: PreviewSettings, save: (PreviewSettings) throws -> Void) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("完整预览选项")
        alert.informativeText = L10n.tr("鼠标停留在条目上后显示完整内容。也可右击预览；列表获得焦点时可按空格。")
        alert.addButton(withTitle: L10n.tr("保存"))
        alert.addButton(withTitle: L10n.tr("取消"))
        let enabled = NSButton(checkboxWithTitle: L10n.tr("启用鼠标悬浮预览"), target: nil, action: nil)
        enabled.state = current.hoverEnabled ? .on : .off
        let field = NSTextField(string: String(format: "%.1f", current.hoverDelay))
        field.setAccessibilityLabel(L10n.tr("悬浮预览等待秒数，0.2 到 5 秒"))
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let row = NSStackView(views: [NSTextField(labelWithString: L10n.tr("等待")), field,
                                    NSTextField(labelWithString: L10n.tr("秒（0.2–5，默认 1）"))])
        let stack = NSStackView(views: [enabled, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.frame = NSRect(x: 0, y: 0, width: 350, height: 70)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let seconds = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  seconds.isFinite, PreviewSettings.delayRange.contains(seconds) else {
                alert.informativeText = L10n.tr("请输入 0.2 到 5 之间的秒数，例如 0.5、1、1.5。")
                continue
            }
            do {
                try save(PreviewSettings(hoverEnabled: enabled.state == .on, hoverDelay: seconds))
                return
            } catch {
                alert.informativeText = L10n.tr("设置保存失败，原设置未改变。请检查数据目录是否可写，或通过“数据与恢复”重试。")
            }
        }
    }
}
