import AppKit

final class TextPreviewViewController: NSViewController {
    let textView = PreviewTextView()
    let scrollView = NSScrollView()
    let formatting: JSONPreviewFormattingController?
    private let status = NSTextField(wrappingLabelWithString: "选取文字后按 ⌘C，可复制到历史记录")
    var onCopyText: ((String) -> Bool)?
    private let text: String

    init(text: String, allowsJSONFormatting: Bool = true) {
        self.text = text
        formatting = allowsJSONFormatting ? JSONPreviewFormattingController(original: text) : nil
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
        textView.string = text
        textView.setAccessibilityLabel("完整内容，可选择部分文字复制")
        textView.onCopyText = { [weak self] text in
            let success = self?.onCopyText?(text) == true
            self?.status.stringValue = success ? "已复制选中文本并加入历史" : "复制失败，原内容仍保留"
            self?.status.textColor = success ? .secondaryLabelColor : .systemRed
            return success
        }
        scrollView.documentView = textView
        let copyButton = NSButton(title: "复制选中文本", target: textView, action: #selector(NSText.copy(_:)))
        copyButton.bezelStyle = .rounded
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var buttons: [NSView] = []
        if let formatting {
            buttons = [formatting.formatButton, formatting.originalButton]
            formatting.onDisplayText = { [weak self] text in self?.displayText(text) }
            formatting.onStatus = { [weak self] message, isError in
                self?.status.stringValue = message
                self?.status.textColor = isError ? .systemRed : .secondaryLabelColor
            }
        }
        let toolbar = NSStackView(views: buttons + [NSView(), copyButton])
        toolbar.spacing = 8
        let stack = NSStackView(views: [toolbar, scrollView, status])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalTo: view.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func displayText(_ text: String) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: max(textView.frame.height, scrollView.contentSize.height)))
    }
}
