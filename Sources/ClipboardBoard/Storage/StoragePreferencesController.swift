import ClipboardCore
import AppKit

/// Directory picker and migration progress. The app owns the migration itself.
final class StoragePreferencesController: NSWindowController {
    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let change = NSButton(title:L10n.tr("更改存储位置…"),target:nil,action:nil)
    private var directory = URL(fileURLWithPath:"/")
    private(set) var isMigrating = false
    var onMove: ((URL, @escaping (Result<URL,Error>) -> Void) -> Void)?
    var isVisible: Bool { window?.isVisible == true }
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:300),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = L10n.tr("存储位置");window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString:L10n.tr("历史、收藏与设置的存储位置"))
        title.font = .systemFont(ofSize:17,weight:.semibold)
        pathLabel.isSelectable = true;pathLabel.maximumNumberOfLines = 4
        pathLabel.setAccessibilityLabel(L10n.tr("当前数据存储目录"))
        let detail = NSTextField(wrappingLabelWithString:L10n.tr("退出或电脑重启后仍从此处恢复。新位置会创建 ClipboardBoardData 文件夹；迁移校验成功后才切换，旧目录保留副本。"))
        detail.font = .systemFont(ofSize:12);detail.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize:12);status.maximumNumberOfLines = 4
        let open = NSButton(title:L10n.tr("打开当前目录"),target:self,action:#selector(openDirectory))
        change.target = self;change.action = #selector(chooseDirectory)
        change.toolTip = L10n.tr("请选择稳定可写的目录；云盘目录可能由其客户端同步，应用不主动联网。")
        [open,change].forEach { $0.bezelStyle = .rounded }
        let buttons = NSStackView(views:[open,NSView(),change])
        let stack = NSStackView(views:[title,pathLabel,detail,NSView(),status,buttons])
        stack.orientation = .vertical;stack.alignment = .width;stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),
            stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),
            stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),
            stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-20)
        ])
        [title,pathLabel,detail,status].forEach { $0.alignment = .left; $0.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(directory:URL) {
        self.directory = directory;pathLabel.stringValue = directory.path
        if !isMigrating { status.stringValue = L10n.tr("收藏独立保存，不受普通历史的 50 条上限影响。");status.textColor = .secondaryLabelColor }
        if !isVisible { window?.center() }
        NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    @objc private func openDirectory() { NSWorkspace.shared.open(directory) }
    @objc private func chooseDirectory() {
        guard !isMigrating, let window else { return }
        let picker = NSOpenPanel();picker.canChooseFiles = false;picker.canChooseDirectories = true
        picker.canCreateDirectories = true;picker.allowsMultipleSelection = false
        picker.prompt = L10n.tr("选择存放位置");picker.message = L10n.tr("在所选目录下创建 ClipboardBoardData；已有数据不会被覆盖。")
        picker.beginSheetModal(for:window) { [weak self] result in
            guard result == .OK, let url = picker.url, let self else { return }
            let target = url.appendingPathComponent("ClipboardBoardData",isDirectory:true)
            let alert = NSAlert();alert.messageText = L10n.tr("迁移到新存储位置？")
            alert.informativeText = target.path + L10n.tr("\n\n将复制历史、收藏与设置并校验。旧目录保留副本，切换后不会自动合并旧副本。")
            alert.addButton(withTitle:L10n.tr("迁移并使用"));alert.addButton(withTitle:L10n.tr("取消"))
            alert.beginSheetModal(for:window) { [weak self] choice in
                guard choice == .alertFirstButtonReturn, let self else { return }
                self.isMigrating = true;self.change.isEnabled = false
                self.status.stringValue = L10n.tr("正在迁移并校验…新复制暂存于内存，完成后保存。")
                self.onMove?(target) { [weak self] result in
                    guard let self else { return }
                    self.isMigrating = false;self.change.isEnabled = true
                    switch result {
                    case .success(let url):self.directory = url;self.pathLabel.stringValue = url.path;self.status.stringValue = L10n.tr("已切换到新位置。旧目录仍保留副本。");self.status.textColor = .secondaryLabelColor
                    case .failure(let error):self.status.stringValue = error.localizedDescription;self.status.textColor = .systemRed
                    }
                }
            }
        }
    }
}
