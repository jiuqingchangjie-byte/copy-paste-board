import ClipboardCore
import AppKit

final class FavoritesListTable: NSTableView {
    var onPreview: (() -> Void)?
    var onRemove: (() -> Void)?
    var onCopy: (() -> Void)?
    @objc func copy(_ sender: Any?) { if isEnabled { onCopy?() } }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if !event.isARepeat, [UInt16(36),76,49].contains(event.keyCode) { onPreview?(); return }
        if event.keyCode == 51, event.modifierFlags.contains(.command) { onRemove?(); return }
        super.keyDown(with: event)
    }
}

/// Native split library layout; no persistence or mutation decisions here.
final class FavoritesLibraryView: NSView {
    let folders = NSTableView()
    let entries = FavoritesListTable()
    let search = NSSearchField()
    let heading = NSTextField(labelWithString: L10n.tr("全部收藏"))
    let status = NSTextField(wrappingLabelWithString: L10n.tr("收藏独立保存，不占普通历史额度"))
    let pageLabel = NSTextField(labelWithString: "")
    let newFolder = NSButton(title: L10n.tr("新建文件夹"), target: nil, action: nil)
    let folderMenu = NSButton(title: L10n.tr("目录管理…"), target: nil, action: nil)
    let preview = NSButton(title: L10n.tr("查看完整内容"), target: nil, action: nil)
    let copy = NSButton(title: L10n.tr("复制内容"), target: nil, action: nil)
    let move = NSButton(title: L10n.tr("移动到…"), target: nil, action: nil)
    let remove = NSButton(title: L10n.tr("取消收藏"), target: nil, action: nil)
    let clear = NSButton(title: L10n.tr("清空收藏库…"), target: nil, action: nil)
    let previous = NSButton(title: L10n.tr("上一页"), target: nil, action: nil)
    let next = NSButton(title: L10n.tr("下一页"), target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        let folderColumn = NSTableColumn(identifier: .init("folder"))
        folders.addTableColumn(folderColumn)
        folders.headerView = nil
        folders.rowHeight = 34
        folders.style = .sourceList
        folders.allowsEmptySelection = false
        folders.setAccessibilityLabel(L10n.tr("收藏文件夹"))
        let folderScroll = NSScrollView()
        folderScroll.documentView = folders
        folderScroll.hasVerticalScroller = true
        let sidebarHeading = NSTextField(labelWithString: L10n.tr("收藏库"))
        sidebarHeading.alignment = .left
        let sidebar = NSStackView(views: [sidebarHeading,folderScroll,newFolder,folderMenu])
        sidebar.orientation = .vertical
        sidebar.alignment = .width
        sidebar.spacing = 10
        sidebar.widthAnchor.constraint(equalToConstant: 240).isActive = true
        [sidebarHeading,folderScroll,newFolder,folderMenu].forEach { $0.widthAnchor.constraint(equalTo:sidebar.widthAnchor).isActive = true }
        for (id,title,width) in [("title",L10n.tr("内容"),330.0),("kind",L10n.tr("类型"),60.0),("source",L10n.tr("来源"),110.0)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
            entries.addTableColumn(column)
        }
        entries.rowHeight = 42
        entries.usesAlternatingRowBackgroundColors = true
        entries.allowsMultipleSelection = true
        entries.allowsEmptySelection = true
        entries.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        entries.setAccessibilityLabel(L10n.tr("收藏内容，支持 Command 或 Shift 多选"))
        let list = NSScrollView()
        list.documentView = entries
        list.hasVerticalScroller = true
        list.hasHorizontalScroller = true
        list.borderType = .bezelBorder
        search.placeholderString = L10n.tr("搜索当前目录的内容或来源")
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel(L10n.tr("搜索收藏"))
        (search.cell as? NSSearchFieldCell)?.searchButtonCell?.setAccessibilityLabel(L10n.tr("搜索"))
        (search.cell as? NSSearchFieldCell)?.cancelButtonCell?.setAccessibilityLabel(L10n.tr("取消"))
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        pageLabel.font = .systemFont(ofSize: 12)
        let actions = NSStackView(views: [preview,copy,move,remove,NSView()])
        actions.spacing = 8
        let pages = NSStackView(views: [pageLabel,NSView(),previous,next])
        pages.spacing = 8
        let top = NSStackView(views: [heading,NSView(),clear])
        let main = NSStackView(views: [top,search,actions,list,pages,status])
        main.orientation = .vertical
        main.alignment = .width
        main.spacing = 12
        let divider = NSBox(); divider.boxType = .separator; divider.widthAnchor.constraint(equalToConstant:1).isActive = true
        let content = NSStackView(views: [sidebar,divider,main])
        content.spacing = 18
        content.alignment = .height
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            main.widthAnchor.constraint(equalTo:content.widthAnchor,constant:-277),
            list.widthAnchor.constraint(equalTo:main.widthAnchor),
            status.widthAnchor.constraint(equalTo:main.widthAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            list.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            folderScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        for button in [newFolder,folderMenu,preview,copy,move,remove,clear,previous,next] { button.bezelStyle = .rounded }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
