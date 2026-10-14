import AppKit

/// Draws the menu bar icon: a small rounded window with a prompt chevron and cursor, followed by the
/// running-server count when it's above zero. A template image, so macOS tints it for the
/// menu bar's appearance.
enum MenuBarGlyph {
    @MainActor
    static func image(count: Int) -> NSImage {
        let glyphSize = NSSize(width: 18, height: 16)
        let countText = count > 0 ? NSAttributedString(string: count > 99 ? "99+" : String(count), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold).rounded,
            .foregroundColor: NSColor.black,
        ]) : nil
        let textWidth = countText.map { ceil($0.size().width) + 3 } ?? 0
        let size = NSSize(width: glyphSize.width + textWidth, height: glyphSize.height)

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Window outline.
            let frame = NSRect(x: 1.5, y: 1.75, width: 15, height: 12.5)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3.4, yRadius: 3.4)
            outline.lineWidth = 1.5
            outline.stroke()

            // Prompt chevron and cursor, centred in the window.
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: 5.2, y: 10.2))
            chevron.line(to: NSPoint(x: 7.9, y: 8))
            chevron.line(to: NSPoint(x: 5.2, y: 5.8))
            chevron.lineWidth = 1.5
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 9.6, y: 5.9))
            cursor.line(to: NSPoint(x: 12.9, y: 5.9))
            cursor.lineWidth = 1.5
            cursor.lineCapStyle = .round
            cursor.stroke()

            if let countText {
                let textSize = countText.size()
                countText.draw(at: NSPoint(x: glyphSize.width + 2, y: (size.height - textSize.height) / 2))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = count == 0
            ? "\(AppInfo.name), no servers running"
            : "\(AppInfo.name), \(count) \(count == 1 ? "server" : "servers") running"
        return image
    }
}

private extension NSFont {
    var rounded: NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
