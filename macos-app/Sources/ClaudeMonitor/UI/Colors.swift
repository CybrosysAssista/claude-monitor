import AppKit

enum ThresholdColors {
    /// macOS system colors (auto-adapting for light/dark) for four tiers,
    /// with the 50–79 tier preserving the original emerald-400 hex from the
    /// GNOME extension for a familiar green-on-green step.
    static func color(forRemainingPct remaining: Double?) -> NSColor {
        guard let v = remaining else { return .secondaryLabelColor }
        if v >= 80 { return .systemGreen }
        if v >= 50 { return NSColor(hex: 0x34d399) }
        if v >= 30 { return .systemYellow }
        if v >= 15 { return .systemOrange }
        return .systemRed
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xff) / 255
        let g = CGFloat((hex >> 8) & 0xff) / 255
        let b = CGFloat(hex & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
