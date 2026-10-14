import Foundation

/// The product name in one place, so renaming the app is a one-line change here plus the
/// display name in the target's build settings (INFOPLIST_KEY_CFBundleDisplayName).
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Portly"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
