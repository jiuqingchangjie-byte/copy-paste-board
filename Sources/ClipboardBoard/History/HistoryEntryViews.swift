import AppKit
import ClipboardCore

final class ClipRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 4), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        path.stroke()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 4), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

final class ClipCellView: NSTableCellView {
    private let favoriteButton = NSButton()
    private var favoriteAction: (() -> Void)?
    private var rowTrailing: NSLayoutConstraint!
    private let preview = NSImageView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 7
        preview.layer?.masksToBounds = true
        title.font = .systemFont(ofSize: 13)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [title, preview, detail])
        row.orientation = .vertical
        row.spacing = 7
        row.alignment = .leading
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        rowTrailing = row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalTo: row.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 84),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowTrailing,
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalTo: row.widthAnchor),
            detail.widthAnchor.constraint(equalTo: row.widthAnchor)
        ])
        textField = title
        favoriteButton.isBordered = false;favoriteButton.isHidden = true
        favoriteButton.target = self;favoriteButton.action = #selector(toggleFavorite)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(favoriteButton)
        NSLayoutConstraint.activate([favoriteButton.trailingAnchor.constraint(equalTo: trailingAnchor,constant:-8),favoriteButton.topAnchor.constraint(equalTo:topAnchor,constant:10),favoriteButton.widthAnchor.constraint(equalToConstant:22),favoriteButton.heightAnchor.constraint(equalToConstant:22)])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureFavorite(_ saved: Bool, action: @escaping () -> Void) {
        favoriteAction = action;favoriteButton.isHidden = false;rowTrailing.constant = -38
        favoriteButton.image = NSImage(systemSymbolName: saved ? "star.fill" : "star",accessibilityDescription:nil)
        favoriteButton.contentTintColor = saved ? .systemOrange : .secondaryLabelColor
        favoriteButton.setAccessibilityLabel(saved ? L10n.tr("取消收藏此条内容") : L10n.tr("收藏此条内容"))
        favoriteButton.toolTip = saved ? L10n.tr("取消收藏") : L10n.tr("收藏到未分类")
    }
    @objc private func toggleFavorite() { favoriteAction?() }

    func configure(_ entry: HistoryEntry) {
        var kind: String
        switch entry.payload {
        case .text(let text):
            preview.isHidden = true
            title.stringValue = String(text.prefix(500)).replacingOccurrences(of: "\n", with: "  ")
                .replacingOccurrences(of: "\r", with: " ")
            preview.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: L10n.tr("文本"))
            preview.contentTintColor = .secondaryLabelColor
            kind = L10n.tr("文本 · {0} 字符", String(describing: text.count))
        case .image(let data):
            title.isHidden = true
            let image = NSImage(data: data)
            preview.image = image
            title.stringValue = L10n.tr("图片")
            if let rep = image?.representations.first {
                kind = L10n.tr("图片 · {0} × {1}", String(describing: rep.pixelsWide), String(describing: rep.pixelsHigh))
            } else { kind = L10n.tr("图片") }
        case .files(let paths):
            preview.isHidden = true
            let urls = paths.compactMap(URL.init(string:))
            title.stringValue = urls.map(\.lastPathComponent).joined(separator: "、")
            preview.image = NSImage(systemSymbolName: paths.count > 1 ? "doc.on.doc" : "doc", accessibilityDescription: L10n.tr("文件"))
            preview.contentTintColor = .secondaryLabelColor
            kind = L10n.tr("{0} 个文件", String(describing: paths.count))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.language.locale
        formatter.unitsStyle = .short
        let source = entry.sourceName.isEmpty ? "" : " · \(L10n.sourceName(entry.sourceName))"
        let age = Date().timeIntervalSince(entry.copiedAt)
        let time = age < 60 ? L10n.tr("刚刚") : formatter.localizedString(for: entry.copiedAt, relativeTo: Date())
        detail.stringValue = "\(kind)\(source) · \(time)"
        setAccessibilityLabel("\(title.stringValue)，\(detail.stringValue)")
    }
}
