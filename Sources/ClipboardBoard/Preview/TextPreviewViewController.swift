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
        let copy = menu.addItem(withTitle: "复制选中文本", action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        let select = menu.addItem(withTitle: "全选", action: #selector(selectAll(_:)), keyEquivalent: "")
        select.target = self
        return menu
    }
}

final class TextPreviewViewController: NSViewController {
    let textView = PreviewTextView()
    let scrollView = NSScrollView()
    private let status = NSTextField(labelWithString: "选取文字后按 ⌘C，可复制到历史记录")
    var onCopyText: ((String) -> Bool)?
    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 450, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text // Never truncate, normalize line endings, or parse markup.
        textView.setAccessibilityLabel("完整内容，可选择部分文字复制")
        textView.onCopyText = { [weak self] text in
            let success = self?.onCopyText?(text) == true
            self?.status.stringValue = success ? "已复制选中文本并加入历史" : "复制失败，原内容仍保留"
            return success
        }
        scrollView.documentView = textView
        let copyButton = NSButton(title: "复制选中文本", target: textView, action: #selector(NSText.copy(_:)))
        copyButton.bezelStyle = .rounded
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [status, NSView(), copyButton])
        footer.spacing = 8
        let stack = NSStackView(views: [scrollView, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: max(textView.frame.height, scrollView.contentSize.height)))
    }
}
