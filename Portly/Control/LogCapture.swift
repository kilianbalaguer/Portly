import Foundation
import Observation

struct LogLine: Identifiable, Sendable, Equatable {
    var id: Int
    var text: String
    /// Lines Portly writes itself, such as "Restarted", styled differently in the log view.
    var isMarker = false
}

/// The captured output of one server we launched: an in-memory ring buffer of recent lines.
@MainActor
@Observable
final class LogSession {
    static let capacity = 5_000

    private(set) var lines: [LogLine] = []
    @ObservationIgnored private var nextID = 0

    func append(_ text: String) {
        let new = LogText.lines(from: text)
        guard !new.isEmpty else { return }
        lines.reserveCapacity(Self.capacity + 512)
        for line in new {
            lines.append(LogLine(id: nextID, text: line))
            nextID += 1
        }
        trim()
    }

    func appendMarker(_ text: String) {
        lines.append(LogLine(id: nextID, text: text, isMarker: true))
        nextID += 1
        trim()
    }

    /// Drops the oldest lines in batches so trimming isn't paid on every append.
    private func trim() {
        if lines.count > Self.capacity + 256 {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    var lastMeaningfulLine: String? {
        lines.last { !$0.isMarker && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }?.text
    }
}

enum LogText {
    /// Splits raw output into display lines: strips ANSI escape sequences and resolves carriage
    /// returns the way a terminal would (only the last redraw of a progress line is kept).
    static func lines(from text: String) -> [String] {
        // "\r\n" is a single Character in Swift, so it must be matched explicitly.
        var parts = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }.map(String.init)
        if parts.last == "" { parts.removeLast() }
        return parts.map { line in
            var line = stripANSI(line)
            if line.hasSuffix("\r") { line.removeLast() }
            if let lastCR = line.lastIndex(of: "\r") {
                line = String(line[line.index(after: lastCR)...])
            }
            return line
        }
    }

    static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        var output = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1B}" else {
                output.append(scalar)
                continue
            }
            switch scalars.next() {
            case "[":  // CSI: parameters, then a final byte in @…~
                while let next = scalars.next(), !(0x40...0x7E).contains(next.value) {}
            case "]":  // OSC: until BEL or ESC \
                while let next = scalars.next(), next != "\u{07}" {
                    if next == "\u{1B}" { _ = scalars.next(); break }
                }
            default:
                break  // two-byte sequence, already consumed
            }
        }
        return String(output)
    }
}

/// Follows a log file that a launched server appends to. Lives off the main actor.
actor LogTailer {
    /// Past this size the file is truncated; the in-memory buffer still holds recent lines.
    static let maxFileSize: UInt64 = 8 << 20

    nonisolated let url: URL
    private var offset: UInt64 = 0
    private var pending = Data()

    init(url: URL) {
        self.url = url
    }

    /// Returns new complete lines since the last call. A trailing partial line is held back
    /// until more output arrives, or returned as-is once output has gone quiet.
    func read() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }  // truncated
        var chunk = Data()
        if size > offset {
            try? handle.seek(toOffset: offset)
            chunk = (try? handle.readToEnd()) ?? Data()
            offset += UInt64(chunk.count)
        }
        if offset > Self.maxFileSize {
            truncate(url.path, 0)
            offset = 0
        }

        if chunk.isEmpty {
            guard !pending.isEmpty else { return nil }
            defer { pending.removeAll() }
            return String(decoding: pending, as: UTF8.self) + "\n"
        }
        pending.append(chunk)
        guard let lastNewline = pending.lastIndex(of: UInt8(ascii: "\n")) else { return nil }
        let complete = pending[...lastNewline]
        let text = String(decoding: complete, as: UTF8.self)
        pending = Data(pending[pending.index(after: lastNewline)...])
        return text
    }
}

enum LogFiles {
    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Portly").appendingPathComponent("Logs")
    }

    static func newFile() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        return url
    }

    /// Removes logs from earlier sessions. A server still writing to one keeps its open file.
    static func removeStale() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "log" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
