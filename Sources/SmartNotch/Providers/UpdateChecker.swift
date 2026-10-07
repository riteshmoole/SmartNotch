import AppKit

/// Checks GitHub Releases for a newer version at launch and once a day. No Sparkle: unnotarized
/// updates would hit Gatekeeper anyway, so we badge the notch's gear icon and link to the download.
/// Disabled until `repository` is set.
@MainActor
final class UpdateChecker: ObservableObject {
    /// "owner/repo" on GitHub. Leave empty to make no network requests at all.
    static let repository = "riteshmoole/SmartNotch"
    /// Always serves the newest release's ZIP.
    static let downloadURL = URL(string: "https://github.com/\(repository)/releases/latest/download/SmartNotch.zip")!

    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?
    /// First paragraph of the release notes (the summary passed to the release script).
    @Published private(set) var releaseSummary: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckFailed = false

    private var timer: Timer?

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isNewer(latest, than: currentVersion)
    }

    /// Numeric, per-component comparison, so "0.1.10" is newer than "0.1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
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
        guard !Self.repository.isEmpty, !isChecking,
              let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SmartNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        isChecking = true
        Task {
            defer { self.isChecking = false; self.lastChecked = Date() }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                self.lastCheckFailed = true
                return
            }
            self.lastCheckFailed = false
            self.latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            self.releaseURL = (json["html_url"] as? String).flatMap(URL.init(string:))
            self.releaseSummary = (json["body"] as? String).flatMap(Self.summary(fromNotes:))
        }
    }

    func setDemo(latest: String, summary: String) {
        latestVersion = latest
        releaseSummary = summary
        releaseURL = URL(string: "https://github.com/\(Self.repository)/releases/latest")
    }

    /// The text before the first blank line, as plain text, capped so a long note can't blow up the layout.
    private static func summary(fromNotes body: String) -> String? {
        let first = body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty else { return nil }
        let plain = (try? AttributedString(markdown: first)).map { String($0.characters) } ?? first
        return String(plain.prefix(400)).displaySafe
    }
}
