#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Generates the README's images from the real UI, against whatever servers are running:
///   -PortlyReadmeAssets <port-to-restart> <dir>
/// Writes logo.png, hero.png and demo.gif. Restarts the server on the given port for real so the
/// demo can show a restart and captured logs.
@MainActor
enum ReadmeAssets {
    static func run(_ delegate: AppDelegate, restartPort: Int, directory: String) async {
        let store = delegate.store
        await store.refresh()
        write(render(Logo(size: 128), delegate), to: directory + "/logo.png")

        var frames: [(NSBitmapImageRep, Double)] = []
        func frame(_ hold: Double, logs: UUID? = nil) {
            if let rep = render(DemoCanvas(logTarget: logs), delegate) { frames.append((rep, hold)) }
        }

        // 1. All servers.
        frame(1.6)
        // 2. Type to filter.
        for prefix in ["s", "st", "sto", "stor", "store"] {
            store.searchText = prefix
            frame(0.14)
        }
        frame(1.3)
        store.searchText = ""

        // 3. Restart for real: stopping → starting → back with captured logs.
        guard let server = store.servers.first(where: { $0.primaryPort == restartPort }) else { return }
        var launched: ManagedServer?
        store.restart(server) { launched = $0 }
        for _ in 0..<60 where launched == nil {
            try? await Task.sleep(for: .milliseconds(120))
            if store.activity[server.pid] != nil || store.managed.contains(where: { $0.state == .starting }) {
                if frames.count < 12 { frame(0.5) }
            }
        }
        guard let entry = launched else { return }
        for _ in 0..<30 where entry.state == .starting {
            try? await Task.sleep(for: .milliseconds(150))
            await store.refresh()
        }
        frame(0.6)
        try? await Task.sleep(for: .seconds(2.5))   // let the request loop fill the log
        await store.refresh()
        frame(1.4)
        // 4. Logs.
        frame(2.8, logs: entry.id)

        writeGIF(frames, to: directory + "/demo.gif")
        write(render(Hero(logTarget: entry.id), delegate), to: directory + "/hero.png")
    }

    // MARK: Rendering

    static func render<V: View>(_ view: V, _ delegate: AppDelegate) -> NSBitmapImageRep? {
        let root = view
            .environment(delegate.store)
            .environment(delegate.popover)
            .environment(delegate.settings)
            .environment(delegate)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: -6000, y: 0, width: 400, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    static func write(_ rep: NSBitmapImageRep?, to path: String) {
        try? rep?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func writeGIF(_ frames: [(NSBitmapImageRep, Double)], to path: String) {
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (rep, hold) in frames {
            // Half resolution keeps the GIF small; it's still crisp at its README display size.
            guard let image = rep.cgImage, let scaled = downscale(image, by: 2) else { continue }
            CGImageDestinationAddImage(destination, scaled, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: hold]] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
    }

    private static func downscale(_ image: CGImage, by factor: Int) -> CGImage? {
        let width = image.width / factor, height = image.height / factor
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

// MARK: Scenes

/// Deep night-blue canvas with a soft periwinkle glow, shared by the hero and the demo.
private struct Canvas: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.09), Color(red: 0.08, green: 0.08, blue: 0.17)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.accent.opacity(0.30), .clear], center: UnitPoint(x: 0.78, y: 0.12), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.accent.opacity(0.14), .clear], center: UnitPoint(x: 0.1, y: 0.95), startRadius: 0, endRadius: 420)
        }
    }
}

/// The popover (or a log screen) as a floating card.
private struct Card<Content: View>: View {
    var width: CGFloat = 360
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: width)
            .background(Color(white: 0.115))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.55), radius: 40, y: 22)
    }
}

private struct DemoCanvas: View {
    let logTarget: UUID?

    var body: some View {
        ZStack(alignment: .top) {
            Canvas()
            Card {
                if let logTarget {
                    LogScreen(target: .managed(logTarget), onBack: {})
                } else {
                    PopoverView()
                }
            }
            .padding(.top, 40)
        }
        .frame(width: 520, height: 520)
    }
}

private struct Hero: View {
    let logTarget: UUID

    var body: some View {
        ZStack {
            Canvas()
            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: 18) {
                    Logo(size: 76)
                    Text("Portly")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Every dev server on your Mac,\none keystroke away.")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(3)
                    HStack(spacing: 6) {
                        ForEach(["⌃", "⌥", "L"], id: \.self) { key in
                            Text(key)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(minWidth: 34, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.16)))
                        }
                    }
                    .padding(.top, 6)
                }
                ZStack(alignment: .topLeading) {
                    Card(width: 300) {
                        LogScreen(target: .managed(logTarget), onBack: {})
                            .frame(height: 330, alignment: .top)
                            .clipped()
                    }
                    .offset(x: 200, y: 70)
                    Card { PopoverView() }
                }
                .frame(width: 520, height: 470, alignment: .topLeading)
            }
        }
        .frame(width: 1200, height: 620)
    }
}

/// App mark: the menu bar glyph on a deep indigo squircle.
struct Logo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.28, blue: 0.62), Color(red: 0.10, green: 0.10, blue: 0.25)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: max(1, size / 128))
            Image(nsImage: MenuBarGlyph.image(count: 0))
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.80, green: 0.82, blue: 1)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.56)
                .shadow(color: Theme.accent.opacity(0.8), radius: size * 0.08)
        }
        .frame(width: size, height: size)
    }
}
#endif
