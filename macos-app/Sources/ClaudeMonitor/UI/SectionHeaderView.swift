import AppKit

/// Custom NSMenuItem.view for provider section headers.
/// NSMenuItem(title: …) with isEnabled=false dims the title — using a custom
/// view bypasses that and gives us full control over font weight + color.
final class SectionHeaderView: NSView {
    private let iconView: NSImageView
    private let titleLabel: NSTextField

    init(title: String, icon: NSImage?) {
        self.iconView = NSImageView()
        self.iconView.image = icon
        self.iconView.imageScaling = .scaleProportionallyDown

        self.titleLabel = NSTextField(labelWithString: title)
        self.titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        self.titleLabel.textColor = .labelColor
        self.titleLabel.isBezeled = false
        self.titleLabel.drawsBackground = false
        self.titleLabel.isEditable = false

        super.init(frame: NSRect(x: 0, y: 0, width: 366, height: 22))

        iconView.frame    = NSRect(x: 12, y: 3, width: 16, height: 16)
        titleLabel.frame  = NSRect(x: 32, y: 2, width: 200, height: 17)

        addSubview(iconView)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}
