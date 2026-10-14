import SwiftUI

struct PopoverView: View {
    @Environment(ServerStore.self) private var store
    @Environment(PopoverState.self) private var popover
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var logTarget: LogTarget?
    @State private var selectedID: String?
    @State private var keyboardActive = false
    @State private var keyMonitor = PopoverKeyMonitor()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            if let logTarget {
                LogScreen(target: logTarget) { showList() }
                    .id(logTarget)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                ListScreen(selectedID: $selectedID, keyboardActive: keyboardActive, searchFocused: $searchFocused) { item in
                    showLogs(for: item)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: Theme.popoverWidth)
        .background(Backdrop(colorScheme: colorScheme))
        .background(WindowReader(onWindow: { window in
            keyMonitor.window = window
        }, onOpenChange: { open in
            popover.setOpen(open)
        }))
        .onAppear {
            keyMonitor.handler = handleKey
            keyMonitor.install()
            searchFocused = true
        }
        .onDisappear { keyMonitor.remove() }
        .onChange(of: popover.isOpen) { _, open in
            if open {
                searchFocused = logTarget == nil
            } else {
                store.searchText = ""
                keyboardActive = false
                selectedID = nil
            }
        }
        .onChange(of: popover.hotKeyOpenCount) {
            logTarget = nil
            store.searchText = ""
            searchFocused = true
        }
        .onChange(of: store.searchText) {
            // Typing re-targets Return at the top result.
            selectedID = nil
        }
    }

    // MARK: Navigation

    private func showLogs(for item: ServerListItem) {
        let target: LogTarget = switch item {
        case .server(let server, let managed): managed.map { .managed($0.id) } ?? .external(pid: server.pid)
        case .pending(let entry): .managed(entry.id)
        }
        withAnimation(.localhost(reduceMotion: reduceMotion)) { logTarget = target }
    }

    private func showList() {
        withAnimation(.localhost(reduceMotion: reduceMotion)) { logTarget = nil }
        searchFocused = true
    }

    /// The highlighted row: the keyboard selection, or the top result.
    private var effectiveSelection: ServerListItem? {
        let items = store.items
        return items.first { $0.id == selectedID } ?? items.first
    }

    private func handleKey(_ key: PopoverKeyMonitor.Key) -> Bool {
        if logTarget != nil {
            guard key == .escape else { return false }
            showList()
            return true
        }
        let items = store.items
        switch key {
        case .up, .down:
            guard !items.isEmpty else { return true }
            keyboardActive = true
            let current = items.firstIndex { $0.id == effectiveSelection?.id } ?? 0
            let next = key == .down ? min(current + 1, items.count - 1) : max(current - 1, 0)
            selectedID = items[next].id
            return true
        case .enter:
            guard let item = effectiveSelection else { return true }
            switch item {
            case .server(let server, _):
                store.open(server)
                MenuBarBridge.toggle()
            case .pending:
                showLogs(for: item)
            }
            return true
        case .escape:
            MenuBarBridge.toggle()
            return true
        }
    }
}

/// The main screen: header, server list, footer.
private struct ListScreen: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    @Binding var selectedID: String?
    let keyboardActive: Bool
    var searchFocused: FocusState<Bool>.Binding
    let onLogs: (ServerListItem) -> Void

    @State private var listHeight: CGFloat = 0
    private let maxListHeight: CGFloat = 392

    var body: some View {
        let items = store.items
        VStack(spacing: 0) {
            header
            if let notice = store.notice {
                NoticeBanner(notice: notice, onDismiss: store.dismissNotice)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            list(items)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            footer(items)
        }
        .animation(.localhost(reduceMotion: reduceMotion), value: store.notice)
    }

    private var header: some View {
        @Bindable var store = store
        return HStack(spacing: 6) {
            SearchField(text: $store.searchText, prompt: "Search port, project, framework",
                        hint: settings.hotKey?.displayString, focus: searchFocused)
            CapsuleToggle(title: "All", isOn: $store.showAll,
                          help: store.showAll ? "Showing every listening process" : "Show all listening processes, not just dev servers")
            IconButton(systemImage: "gearshape", label: "Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(10)
    }

    @ViewBuilder
    private func list(_ items: [ServerListItem]) -> some View {
        let highlighted = keyboardActive || !store.searchText.isEmpty
            ? (items.first { $0.id == selectedID } ?? items.first)?.id
            : nil
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    if items.isEmpty {
                        EmptyStateView(kind: emptyKind) {
                            store.showAll = true
                        }
                        .transition(.opacity)
                    }
                    ForEach(items) { item in
                        row(item, selected: item.id == highlighted)
                            .id(item.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                    }
                }
                .padding(6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                .animation(.localhost(reduceMotion: reduceMotion), value: items.map(\.id))
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(listHeight, 60), maxListHeight))
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
            }
        }
    }

    private var emptyKind: EmptyStateView.Kind {
        if !store.hasCompletedFirstScan { return .scanning }
        if !store.searchText.isEmpty { return .noMatches(store.searchText) }
        return .noServers(hidden: store.hiddenCount)
    }

    @ViewBuilder
    private func row(_ item: ServerListItem, selected: Bool) -> some View {
        switch item {
        case .server(let server, let managed):
            ServerRowView(server: server, managed: managed, isSelected: selected, activity: store.activity[server.pid],
                          actions: RowActions(
                              open: { store.open(server) },
                              copy: { store.copyURL(server) },
                              logs: { onLogs(item) },
                              restart: { store.restart(server) },
                              kill: { store.kill(server) }
                          ))
        case .pending(let entry):
            PendingRowView(entry: entry, isSelected: selected,
                           onLogs: { onLogs(item) },
                           onRestart: { store.restart(entry) },
                           onStop: { store.kill(entry) },
                           onDismiss: { store.forget(entry) })
        }
    }

    private func footer(_ items: [ServerListItem]) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.devServerCount > 0 ? Theme.accent : Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(footerText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.localhost(reduceMotion: reduceMotion), value: footerText)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit \(AppInfo.name). Servers keep running.")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private var footerText: String {
        let count = store.devServerCount
        let servers = count == 0 ? "No servers running" : "\(count) \(count == 1 ? "server" : "servers") running"
        guard store.showAll else { return servers }
        let total = store.servers.count
        return "\(servers) · \(total) \(total == 1 ? "listener" : "listeners")"
    }
}

/// A calm wash of the accent over the window material, strongest top-left.
private struct Backdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 1.0 : 0.55
        ZStack {
            RadialGradient(colors: [Theme.accent.opacity(0.18 * strength), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Theme.accent.opacity(0.07 * strength), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 260)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NoticeBanner: View {
    let notice: Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.danger)
            Text(notice.message)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            IconButton(systemImage: "xmark", label: "Dismiss", size: 18, action: onDismiss)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.danger.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.danger.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
