import AppKit
import SwiftUI

/// A read-only, selectable log view backed by NSTextView. Appends incrementally while the
/// filter is unchanged, and follows the tail while `followsTail` is on. Scrolling up turns
/// following off; scrolling back to the bottom turns it on again.
struct LogTextView: NSViewRepresentable {
    var lines: [LogLine]
    var filter: String
    @Binding var followsTail: Bool

    func makeCoordinator() -> Coordinator { Coordinator(followsTail: $followsTail) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.font = Theme.logFont
        textView.setAccessibilityLabel("Server output")

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.followsTail = $followsTail
        context.coordinator.render(lines: lines, filter: filter, follow: followsTail)
    }

    @MainActor
    final class Coordinator: NSObject {
        var followsTail: Binding<Bool>
        weak var scrollView: NSScrollView?
        private var renderedFilter = ""
        private var renderedFirstID: Int?
        private var renderedLastID: Int?
        private var isScrollingProgrammatically = false

        init(followsTail: Binding<Bool>) {
            self.followsTail = followsTail
        }

        func render(lines: [LogLine], filter: String, follow: Bool) {
            guard let textView = scrollView?.documentView as? NSTextView, let storage = textView.textStorage else { return }
            let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
            let canAppend = query == renderedFilter && renderedFirstID == lines.first?.id && renderedLastID != nil

            let newLines: ArraySlice<LogLine>
            if canAppend, let last = renderedLastID {
                guard let index = lines.lastIndex(where: { $0.id <= last }) else { return }
                newLines = lines[(index + 1)...]
            } else {
                storage.setAttributedString(NSAttributedString())
                newLines = lines[...]
            }
            renderedFilter = query
            renderedFirstID = lines.first?.id
            renderedLastID = lines.last?.id

            let visible = query.isEmpty ? Array(newLines) : newLines.filter { $0.text.lowercased().contains(query) }
            if !visible.isEmpty {
                let chunk = NSMutableAttributedString()
                for line in visible {
                    chunk.append(Self.attributed(line, query: query, leadingNewline: storage.length + chunk.length > 0))
                }
                storage.append(chunk)
            }
            if follow { scrollToEnd() }
        }

        private static func attributed(_ line: LogLine, query: String, leadingNewline: Bool) -> NSAttributedString {
            let text = (leadingNewline ? "\n" : "") + line.text
            let attributes: [NSAttributedString.Key: Any] = line.isMarker
                ? [.font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: LogColors.marker]
                : [.font: Theme.logFont, .foregroundColor: LogColors.text]
            let result = NSMutableAttributedString(string: text, attributes: attributes)
            if !query.isEmpty {
                let ns = text.lowercased() as NSString
                var range = ns.range(of: query)
                while range.location != NSNotFound {
                    result.addAttribute(.backgroundColor, value: LogColors.highlight, range: range)
                    let next = range.location + range.length
                    range = ns.range(of: query, range: NSRange(location: next, length: ns.length - next))
                }
            }
            return result
        }

        private func scrollToEnd() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            isScrollingProgrammatically = true
            documentView.layoutSubtreeIfNeeded()
            let y = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isScrollingProgrammatically = false
        }

        @objc func boundsChanged(_ note: Notification) {
            guard !isScrollingProgrammatically, let scrollView, let documentView = scrollView.documentView else { return }
            let visible = scrollView.contentView.bounds
            let atBottom = visible.maxY >= documentView.bounds.height - 12
            if followsTail.wrappedValue != atBottom {
                followsTail.wrappedValue = atBottom
            }
        }
    }
}

/// Appearance-aware colors for log text. `withAlphaComponent` on a dynamic system color freezes
/// it for the appearance current at call time, so these resolve per appearance instead.
@MainActor
private enum LogColors {
    static let text = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 0.92, alpha: 0.9) : NSColor(white: 0.1, alpha: 0.9)
    }
    static let marker = NSColor(Theme.accent)
    static let highlight = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.62, green: 0.64, blue: 1.00, alpha: 0.32)
            : NSColor(srgbRed: 0.35, green: 0.36, blue: 0.86, alpha: 0.22)
    }
}
