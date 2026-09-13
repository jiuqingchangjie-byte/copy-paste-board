import AppKit
import ClipboardCore

/// Owns JSON presentation state and background work for one immutable preview.
/// Does not know about clipboard history, pasteboard writing, or paste actions.
final class JSONPreviewFormattingController: NSObject {
    let formatButton = NSButton(title: L10n.tr("JSON 格式化"), target: nil, action: nil)
    let originalButton = NSButton(title: L10n.tr("查看原文"), target: nil, action: nil)
    private(set) var isFormatting = false
    private(set) var isShowingFormatted = false
    var onDisplayText: ((String) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    private let original: String
    private var formatted: String?
    private var requestID = 0
    private static let queue = DispatchQueue(label: "ClipboardBoard.JSONFormatting", qos: .userInitiated)

    init(original: String) {
        self.original = original
        super.init()
        formatButton.target = self
        formatButton.action = #selector(formatJSON)
        formatButton.bezelStyle = .rounded
        formatButton.setAccessibilityLabel(L10n.tr("JSON 格式化"))
        originalButton.target = self
        originalButton.action = #selector(showOriginal)
        originalButton.bezelStyle = .rounded
        originalButton.isEnabled = false
    }

    @objc func formatJSON() {
        guard !isFormatting, !isShowingFormatted else { return }
        if let formatted { displayFormatted(formatted); return }
        isFormatting = true
        requestID += 1
        let request = requestID
        let original = original
        formatButton.isEnabled = false
        formatButton.title = L10n.tr("正在格式化…")
        originalButton.isEnabled = true
        onStatus?(L10n.tr("正在格式化 JSON…"), false)
        Self.queue.async { [weak self] in
            // A closed preview does not retain the controller until work completes.
            guard self != nil else { return }
            let result = Result { try JSONTextFormatter.format(original) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == request else { return }
                self.isFormatting = false
                self.formatButton.title = L10n.tr("JSON 格式化")
                switch result {
                case .success(let text):
                    self.formatted = text
                    self.displayFormatted(text)
                case .failure(let error):
                    self.formatButton.isEnabled = true
                    self.originalButton.isEnabled = false
                    self.onStatus?(L10n.tr("格式化失败：{0}。原文未改变。", String(describing: error.localizedDescription)), true)
                }
            }
        }
    }

    private func displayFormatted(_ text: String) {
        isShowingFormatted = true
        formatButton.isEnabled = false
        originalButton.isEnabled = true
        onDisplayText?(text)
        onStatus?(L10n.tr("已格式化 JSON · 可选取复制，历史原文保持不变"), false)
    }

    @objc func showOriginal() {
        requestID += 1 // A pending result must not replace the user's restored original.
        isFormatting = false
        isShowingFormatted = false
        formatButton.title = L10n.tr("JSON 格式化")
        formatButton.isEnabled = true
        originalButton.isEnabled = false
        onDisplayText?(original)
        onStatus?(L10n.tr("已显示原文 · 选取文字后按 ⌘C 可复制到历史"), false)
    }
}
