import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let pollIntervalChoices: [Double] = [1, 2, 5]

    var hotKey: KeyCombo? {
        didSet { save(hotKey, forKey: Keys.hotKey) }
    }

    /// Seconds between scans while the popover is open.
    var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Keys.pollInterval) }
    }

    var showAllByDefault: Bool {
        didSet { defaults.set(showAllByDefault, forKey: Keys.showAll) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let hotKey = "hotKey"
        static let hotKeyCleared = "hotKeyCleared"
        static let pollInterval = "pollInterval"
        static let showAll = "showAllByDefault"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.hotKey), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = defaults.bool(forKey: Keys.hotKeyCleared) ? nil : .default
        }
        let interval = defaults.double(forKey: Keys.pollInterval)
        pollInterval = Self.pollIntervalChoices.contains(interval) ? interval : 2
        showAllByDefault = defaults.bool(forKey: Keys.showAll)
    }

    private func save(_ combo: KeyCombo?, forKey key: String) {
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
            defaults.set(false, forKey: Keys.hotKeyCleared)
        } else {
            defaults.removeObject(forKey: key)
            defaults.set(true, forKey: Keys.hotKeyCleared)
        }
    }
}
