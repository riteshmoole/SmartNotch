import Combine
import SwiftUI

/// Themes are pure data. Bundled JSON lives in Contents/Resources/Themes; users can drop
/// their own *.json into ~/Library/Application Support/SmartNotch/Themes.
struct Theme: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    let accent: String
    let glow: Bool
    let glowColor: String
    let glowRadius: Double

    var backgroundColor: Color { Color(hex: background) }
    var foregroundColor: Color { Color(hex: foreground) }
    var accentColor: Color { Color(hex: accent) }
    var glowSwiftColor: Color { Color(hex: glowColor) }

    static let midnight = Theme(id: "midnight", name: "Midnight", background: "#000000", foreground: "#FFFFFF",
                                accent: "#0A84FF", glow: false, glowColor: "#0A84FF", glowRadius: 0)
}

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [Theme] = []
    @Published private(set) var current: Theme = .midnight

    static var userThemesDir: URL { AppPaths.dir("Themes") }

    init() {
        reload()
        Settings.shared.$themeID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in self?.select(id) }
            .store(in: &bag)
    }

    private var bag = Set<AnyCancellable>()

    func reload() {
        var found: [String: Theme] = [Theme.midnight.id: .midnight]
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Themes"), Self.userThemesDir].compactMap { $0 }
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "json" {
                if let data = try? Data(contentsOf: f), let t = try? JSONDecoder().decode(Theme.self, from: data) {
                    found[t.id] = t
                }
            }
        }
        themes = found.values.sorted { $0.name < $1.name }
        select(Settings.shared.themeID)
    }

    private func select(_ id: String) {
        current = themes.first { $0.id == id } ?? .midnight
    }
}

