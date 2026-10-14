#if DEBUG
import AppKit
import SwiftUI

/// Development-only launch arguments, compiled out of Release builds:
///   -PortlyOpenPopover               open the popover via the hotkey code path
///   -PortlyAppearance dark|light     force an appearance
///   -PortlyGallery <dir>             render static states to PNGs
///   -PortlyAppIcon <dir>                 render the 1024px app icon
///   -PortlyReadmeAssets <port> <dir>     generate the README images (see ReadmeAssets)
///   -PortlyRestartScenario <port> <dir>  really restart the server on <port>, snapshotting each stage
///   -PortlySnapshot <path>           render the popover to a PNG
@MainActor
enum DebugSupport {
    static func handleLaunchArguments(_ delegate: AppDelegate) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "-PortlyAppearance"), index + 1 < args.count {
            NSApp.appearance = NSAppearance(named: args[index + 1] == "dark" ? .darkAqua : .aqua)
        }
        if let index = args.firstIndex(of: "-PortlyAppIcon"), index + 1 < args.count {
            ReadmeAssets.writeAppIcon(delegate, directory: args[index + 1])
        }
        if args.contains("-PortlyOpenPopover") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                delegate.popover.hotKeyPressed()
                if let index = args.firstIndex(of: "-PortlyGallery"), index + 1 < args.count {
                    await DebugSnapshot.runGallery(delegate, directory: args[index + 1])
                }
                if let index = args.firstIndex(of: "-PortlyReadmeAssets"), index + 2 < args.count, let port = Int(args[index + 1]) {
                    await ReadmeAssets.run(delegate, restartPort: port, directory: args[index + 2])
                }
                if let index = args.firstIndex(of: "-PortlyRestartScenario"), index + 2 < args.count, let port = Int(args[index + 1]) {
                    await DebugSnapshot.runRestartScenario(delegate, port: port, directory: args[index + 2])
                }
                if let index = args.firstIndex(of: "-PortlySnapshot"), index + 1 < args.count {
                    try? await Task.sleep(for: .seconds(2))
                    DebugSnapshot.write(delegate, to: args[index + 1])
                }
            }
        }
    }
}

@MainActor
enum DebugSnapshot {
    /// Renders the popover UI offscreen over a solid stand-in for the window material and
    /// writes a PNG. Used for design review while developing; window captures need Screen
    /// Recording permission, this doesn't.
    static func write(_ delegate: AppDelegate, to path: String) {
        write(PopoverView(), delegate, to: path)
    }

    static func write<V: View>(_ view: V, _ delegate: AppDelegate, to path: String, width: CGFloat = 360) {
        let dark = NSApp.effectiveAppearance.isDark
        let root = view
            .environment(delegate.store)
            .environment(delegate.popover)
            .environment(delegate.settings)
            .environment(delegate)
            .background(Color(nsColor: dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.96, alpha: 1)))
        let host = NSHostingView(rootView: root)
        host.appearance = NSApp.effectiveAppearance
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: width, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSApp.effectiveAppearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Renders static states for design review.
    static func runGallery(_ delegate: AppDelegate, directory: String) async {
        await delegate.store.refresh()
        try? await Task.sleep(for: .milliseconds(500))
        if let image = MenuBarBridge.statusButton?.image, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory + "/statusitem.png"))
            try? "\(image.size) count=\(delegate.store.devServerCount) \(image.accessibilityDescription ?? "")"
                .write(toFile: directory + "/statusitem.txt", atomically: true, encoding: .utf8)
        }
        write(delegate, to: directory + "/list.png")
        write(EmptyStateView(kind: .noServers(hidden: 7)).frame(width: 360), delegate, to: directory + "/empty.png")
        delegate.store.searchText = "zzz"
        write(delegate, to: directory + "/nomatch.png")
        delegate.store.searchText = "api"
        write(delegate, to: directory + "/search.png")
        delegate.store.searchText = ""
        if let entry = delegate.store.managed.first {
            write(LogScreen(target: .managed(entry.id), onBack: {}).frame(width: 360), delegate, to: directory + "/logs.png")
        }
    }

    /// Restarts the server on `port` for real and snapshots each stage into `directory`.
    static func runRestartScenario(_ delegate: AppDelegate, port: Int, directory: String) async {
        let store = delegate.store
        await store.refresh()
        guard let server = store.servers.first(where: { $0.primaryPort == port }) else { return }
        write(LogScreen(target: .external(pid: server.pid), onBack: {}), delegate, to: directory + "/logs-external.png")
        write(SettingsView(), delegate, to: directory + "/settings.png", width: 420)
        var launched: ManagedServer?
        store.restart(server) { launched = $0 }
        try? await Task.sleep(for: .milliseconds(300))
        write(delegate, to: directory + "/restarting.png")
        for _ in 0..<40 where launched == nil { try? await Task.sleep(for: .milliseconds(250)) }
        guard let entry = launched else { return }
        try? await Task.sleep(for: .seconds(3))
        await store.refresh()
        write(delegate, to: directory + "/after-restart.png")
        write(LogScreen(target: .managed(entry.id), onBack: {}), delegate, to: directory + "/logs-managed.png")
    }
}
#endif
