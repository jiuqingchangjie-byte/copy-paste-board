import AppKit

/// Keeps the original image data in memory; zoom changes presentation only.
final class ImagePreviewViewController: NSViewController {
    let scrollView = NSScrollView()
    let imageView = NSImageView()
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private var zoomObservation: NSKeyValueObservation?

    init?(data: Data) {
        guard let image = NSImage(data: data),
              let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        imageView.image = image
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 400))
        imageView.frame = NSRect(origin: .zero, size: imageView.image!.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.setAccessibilityLabel("原图，可通过双指缩放或缩放按钮查看")
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.001
        scrollView.maxMagnification = 8
        scrollView.borderType = .bezelBorder
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.widthAnchor.constraint(equalToConstant: 55).isActive = true
        let buttons: [NSView] = [
            NSButton(title: "−", target: self, action: #selector(zoomOut)),
            zoomLabel,
            NSButton(title: "+", target: self, action: #selector(zoomIn)),
            NSButton(title: "原始大小", target: self, action: #selector(actualSize)),
            NSButton(title: "适合窗口", target: self, action: #selector(fitToWindow))
        ]
        let toolbar = NSStackView(views: buttons)
        toolbar.spacing = 8
        let stack = NSStackView(views: [scrollView, toolbar])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalTo: view.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        zoomObservation = scrollView.observe(\.magnification, options: [.initial, .new]) { [weak self] scroll, _ in
            self?.zoomLabel.stringValue = String(format: "%.0f%%", scroll.magnification * 100)
        }
    }

    func setZoom(_ scale: CGFloat) {
        let center = NSPoint(x: imageView.visibleRect.midX, y: imageView.visibleRect.midY)
        scrollView.setMagnification(min(max(scale, scrollView.minMagnification), scrollView.maxMagnification), centeredAt: center)
    }
    @objc func zoomIn() { setZoom(scrollView.magnification * 1.25) }
    @objc func zoomOut() { setZoom(scrollView.magnification / 1.25) }
    @objc func actualSize() { setZoom(1) }
    @objc func fitToWindow() {
        view.layoutSubtreeIfNeeded()
        let size = imageView.frame.size
        guard size.width > 0, size.height > 0 else { return }
        setZoom(min(1, min(scrollView.contentSize.width / size.width, scrollView.contentSize.height / size.height)))
    }
}
