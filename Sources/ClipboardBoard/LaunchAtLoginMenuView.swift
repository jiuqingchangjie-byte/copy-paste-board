import AppKit

/// A persistent menu control so changing the preference also shows its resulting
/// system state, including approval and failure, without closing the menu.
final class LaunchAtLoginMenuView: NSView {
    let toggle = NSSwitch()
    let statusLabel = NSTextField(labelWithString: "")
    private let settingsButton = NSButton(title: "去设置", target: nil, action: nil)
    private let service: LaunchAtLoginService
    private let onOpenSettings: () -> Void
    private var refreshTimer: Timer?
    private var lastStatus: LaunchAtLoginService.Status?
    private var failureMessage: String?

    init(service: LaunchAtLoginService, onOpenSettings: @escaping () -> Void) {
        self.service = service
        self.onOpenSettings = onOpenSettings
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 66))
        let title = NSTextField(labelWithString: "登录时自动启动")
        title.font = .systemFont(ofSize: 13)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("登录时自动启动")
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.font = .systemFont(ofSize: 11)
        settingsButton.contentTintColor = .controlAccentColor
        settingsButton.setContentHuggingPriority(.required, for: .horizontal)

        let top = NSStackView(views: [title, NSView(), toggle])
        top.alignment = .centerY
        top.spacing = 12
        let bottom = NSStackView(views: [statusLabel, NSView(), settingsButton])
        bottom.alignment = .centerY
        bottom.spacing = 6
        let stack = NSStackView(views: [top, bottom])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            top.heightAnchor.constraint(equalToConstant: 28),
            bottom.heightAnchor.constraint(equalToConstant: 18)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard window != nil else { return }
        refresh()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        let status = service.status
        if status != lastStatus { failureMessage = nil }
        lastStatus = status
        // An approval-pending request can be switched off to cancel it, but the
        // subtitle explicitly says it is not active yet.
        toggle.state = status == .enabled || status == .requiresApproval ? .on : .off
        toggle.isEnabled = status != .unknown
        settingsButton.isHidden = status == .enabled || status == .disabled
        let text: String
        switch status {
        case .enabled: text = "已开启"
        case .disabled: text = "已关闭"
        case .requiresApproval: text = "等待系统批准 · 尚未生效"
        case .notFound: text = "尚未找到登录项 · 可尝试开启"
        case .unknown: text = "无法读取系统状态"
        }
        statusLabel.stringValue = failureMessage == nil ? text : "更改失败 · \(text)"
        statusLabel.textColor = failureMessage != nil ? .systemRed
            : status == .requiresApproval ? .systemOrange : .secondaryLabelColor
        statusLabel.toolTip = failureMessage ?? text
        toggle.setAccessibilityHelp(failureMessage ?? statusLabel.stringValue)
    }

    @objc private func toggleChanged() {
        let requested = toggle.state == .on
        toggle.isEnabled = false
        failureMessage = nil
        do {
            try service.setEnabled(requested)
            refresh()
        } catch {
            // Restore the real system value instead of leaving a misleading switch.
            refresh()
            failureMessage = error.localizedDescription
            refresh()
        }
    }

    @objc private func openSettings() { onOpenSettings() }
    deinit { refreshTimer?.invalidate() }
}
