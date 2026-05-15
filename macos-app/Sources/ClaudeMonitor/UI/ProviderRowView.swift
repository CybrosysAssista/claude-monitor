import AppKit

/// Custom row used inside NSMenu via NSMenuItem.view.
/// Layout (manual frames, no Auto Layout — keeps it cheap to construct):
///   [14pt indent] [Label 56pt] [Pct 90pt] [Bar 110pt] [Countdown 96pt] = 14+56+90+110+96 = 366pt
/// Height: 22pt.
final class ProviderRowView: NSView {
    private let label: NSTextField
    private let pctText: NSTextField
    private let bar: BarView
    private let countdown: NSTextField

    private var resetsAt: Date?
    private var inverted: Bool

    init(label: String, remaining: Double?, resetsAt: Date?, inverted: Bool) {
        self.label = Self.makeLabel(text: label, color: .labelColor, align: .left, mono: false)
        self.pctText = Self.makeLabel(text: Formatting.pctLong(remaining, inverted: inverted),
                                      color: ThresholdColors.color(forRemainingPct: remaining),
                                      align: .left, mono: true)
        self.bar = BarView()
        self.countdown = Self.makeLabel(text: Formatting.fmtResets(resetsAt),
                                        color: .secondaryLabelColor, align: .right, mono: false)
        self.resetsAt = resetsAt
        self.inverted = inverted
        super.init(frame: NSRect(x: 0, y: 0, width: 366, height: 22))

        // Bar fill: shows "used" by default, or "left" if inverted.
        let v = (remaining ?? 0)
        let fillPct = inverted ? v : (100 - v)
        bar.fillPct = fillPct
        bar.color = ThresholdColors.color(forRemainingPct: remaining)

        layoutSubviews()
        addSubview(self.label)
        addSubview(self.pctText)
        addSubview(self.bar)
        addSubview(self.countdown)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func layoutSubviews() {
        label.frame     = NSRect(x: 14, y: 3, width: 56, height: 16)
        pctText.frame   = NSRect(x: 70, y: 3, width: 90, height: 16)
        bar.frame       = NSRect(x: 160, y: 7, width: 110, height: 8)
        countdown.frame = NSRect(x: 270, y: 3, width: 86, height: 16)
    }

    /// Called by the live-update timer while the menu is open.
    func refreshCountdown() {
        countdown.stringValue = Formatting.fmtResets(resetsAt)
    }

    private static func makeLabel(text: String, color: NSColor, align: NSTextAlignment, mono: Bool) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        // Mono text is the colored percentage — bump to semibold so colored
        // text reads well against macOS menu translucency. Non-mono = secondary
        // labels (label / countdown), keep at default weight.
        f.font = mono
            ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .semibold)
            : NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
        f.textColor = color
        f.alignment = align
        f.isBezeled = false
        f.isEditable = false
        f.drawsBackground = false
        return f
    }
}

final class BarView: NSView {
    var fillPct: Double = 0   // 0–100
    var color: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 3

        // Track
        NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        // Fill
        let clamped = max(0, min(100, fillPct))
        let w = bounds.width * CGFloat(clamped / 100.0)
        guard w > 0 else { return }
        let fillRect = NSRect(x: 0, y: 0, width: w, height: bounds.height)
        color.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}
