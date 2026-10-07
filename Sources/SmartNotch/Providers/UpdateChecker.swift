import AppKit

/// Once-a-day check of GitHub Releases for a newer version. No Sparkle: unnotarized updates would
/// hit Gatekeeper anyway, so we just link to the download page.
/// Disabled until `repository` is set.
@MainActor
final class UpdateChecker: ObservableObject {
    /// "owner/repo" on GitHub. Leave empty to make no network requests at all.
    static let repository = "riteshmoole/SmartNotch"

    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?

    private var timer: Timer?

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return latest.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    func start() {
        guard !Self.repository.isEmpty, timer == nil else { return }
        check()
        let t = Timer(timeInterval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 3600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    func check() {
        guard !Self.repository.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            self.latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            self.releaseURL = (json["html_url"] as? String).flatMap(URL.init(string:))
        }
    }
}
