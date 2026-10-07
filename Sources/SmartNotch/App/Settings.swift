import Foundation

/// User preferences, persisted in UserDefaults. Every property writes through on change.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // Opening behaviour
    @Published var hoverToOpen: Bool { didSet { d.set(hoverToOpen, forKey: "hoverToOpen") } }
    @Published var hoverDelay: Double { didSet { d.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var showPillOnNotchless: Bool { didSet { d.set(showPillOnNotchless, forKey: "showPillOnNotchless") } }
    @Published var forcePill: Bool { didSet { d.set(forcePill, forKey: "forcePill") } }
    @Published var showWings: Bool { didSet { d.set(showWings, forKey: "showWings") } }
    @Published var hideFromScreenShare: Bool { didSet { d.set(hideFromScreenShare, forKey: "hideFromScreenShare") } }

    // Modules
    @Published var mediaEnabled: Bool { didSet { d.set(mediaEnabled, forKey: "mediaEnabled") } }
    @Published var shelfEnabled: Bool { didSet { d.set(shelfEnabled, forKey: "shelfEnabled") } }
    @Published var shelfAutoClearHours: Int { didSet { d.set(shelfAutoClearHours, forKey: "shelfAutoClearHours") } }
    @Published var clipboardEnabled: Bool { didSet { d.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    @Published var clipboardPersist: Bool { didSet { d.set(clipboardPersist, forKey: "clipboardPersist") } }
    @Published var clipboardExcludedApps: [String] { didSet { d.set(clipboardExcludedApps, forKey: "clipboardExcludedApps") } }
    @Published var callActivityEnabled: Bool { didSet { d.set(callActivityEnabled, forKey: "callActivityEnabled") } }
    @Published var hudReplacement: Bool { didSet { d.set(hudReplacement, forKey: "hudReplacement") } }

    // Appearance
    @Published var themeID: String { didSet { d.set(themeID, forKey: "themeID") } }
    @Published var glowEnabled: Bool { didSet { d.set(glowEnabled, forKey: "glowEnabled") } }

    // Misc
    @Published var checkForUpdates: Bool { didSet { d.set(checkForUpdates, forKey: "checkForUpdates") } }
    @Published var hasCompletedOnboarding: Bool { didSet { d.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }

    static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
    ]

    private init() {
        d.register(defaults: [
            "hoverToOpen": true, "hoverDelay": 0.15, "showPillOnNotchless": true, "forcePill": false,
            "showWings": true, "hideFromScreenShare": true,
            "mediaEnabled": true, "shelfEnabled": true, "shelfAutoClearHours": 24,
            "clipboardEnabled": true, "clipboardPersist": false, "clipboardExcludedApps": Self.defaultExcludedApps,
            "callActivityEnabled": true, "hudReplacement": false,
            "themeID": "midnight", "glowEnabled": true,
            "checkForUpdates": true, "hasCompletedOnboarding": false,
        ])
        hoverToOpen = d.bool(forKey: "hoverToOpen")
        hoverDelay = d.double(forKey: "hoverDelay")
        showPillOnNotchless = d.bool(forKey: "showPillOnNotchless")
        forcePill = d.bool(forKey: "forcePill")
        showWings = d.bool(forKey: "showWings")
        hideFromScreenShare = d.bool(forKey: "hideFromScreenShare")
        mediaEnabled = d.bool(forKey: "mediaEnabled")
        shelfEnabled = d.bool(forKey: "shelfEnabled")
        shelfAutoClearHours = d.integer(forKey: "shelfAutoClearHours")
        clipboardEnabled = d.bool(forKey: "clipboardEnabled")
        clipboardPersist = d.bool(forKey: "clipboardPersist")
        clipboardExcludedApps = d.stringArray(forKey: "clipboardExcludedApps") ?? Self.defaultExcludedApps
        callActivityEnabled = d.bool(forKey: "callActivityEnabled")
        hudReplacement = d.bool(forKey: "hudReplacement")
        themeID = d.string(forKey: "themeID") ?? "midnight"
        glowEnabled = d.bool(forKey: "glowEnabled")
        checkForUpdates = d.bool(forKey: "checkForUpdates")
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
    }
}
