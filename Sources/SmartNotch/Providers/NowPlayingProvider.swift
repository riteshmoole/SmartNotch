import AppKit

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// Elapsed seconds at `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var isPlaying: Bool
    var rate: Double
    var bundleID: String
    var artwork: NSImage?

    func elapsed(at now: Date) -> Double {
        var e = elapsed
        if isPlaying { e += now.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1) }
        if duration > 0 { e = min(e, duration) }
        return max(0, e)
    }

    var appName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum NowPlayingSource: Equatable {
    case disabled
    case starting
    /// Private MediaRemote framework through the bundled perl adapter (all players, including browsers).
    case adapter
    /// Public AppleScript fallback: Music and Spotify only.
    case appleScript
}

/// Now Playing, hybrid strategy:
/// 1. Copy the adapter out of the bundle (quarantine-safe), then `/usr/bin/perl mediaremote-adapter.pl … test`. If it passes, stream JSON updates from `… stream`.
/// 2. If the adapter is missing, fails its test, or crashes 3× in 60 s, poll Music/Spotify via AppleScript.
/// The UI always has a state to render. It never shows a blank panel.
@MainActor
final class NowPlayingProvider: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var source: NowPlayingSource = .disabled

    private var process: Process?
    private var lineBuffer = Data()
    private var payload: [String: Any] = [:]
    private var crashTimes: [Date] = []
    private var stopped = true
    private var fallbackTimer: Timer?
    private var artworkURLLoaded: String?

    // MARK: Adapter files

    /// Bundled adapter files, copied to Application Support on launch (see `installAdapter`).
    private struct AdapterFiles: Sendable {
        let script: URL
        let framework: URL
        let testClient: URL
    }
    private var adapterFiles: AdapterFiles?

    /// A downloaded app carries the com.apple.quarantine flag, and testing showed perl then
    /// refuses to load the quarantined framework, and macOS shows a "can't verify… malware"
    /// alert. An app run straight from Downloads is also translocated to a read-only mount, so we
    /// can't clear the flag in place. Copy the three files into Application Support and clear the
    /// flag on that copy instead.
    /// A stream left behind by a previous SmartNotch that was force-quit or crashed.
    private nonisolated static func killOrphanedStreams() {
        runProcess("/usr/bin/pkill", ["-f", "^/usr/bin/perl .*/SmartNotch/Adapter/[^/]*/mediaremote-adapter[.]pl"], timeout: 3)
    }

    private nonisolated static func installAdapter() -> AdapterFiles? {
        let b = Bundle.main
        guard let script = b.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let fw = b.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: fw.path) else { return nil }
        let client = b.bundleURL.appendingPathComponent("Contents/Helpers/MediaRemoteAdapterTestClient")
        let version = b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let dest = AppPaths.dir("Adapter").appendingPathComponent(version, isDirectory: true)
        let files = AdapterFiles(script: dest.appendingPathComponent(script.lastPathComponent),
                                 framework: dest.appendingPathComponent("MediaRemoteAdapter.framework"),
                                 testClient: dest.appendingPathComponent("MediaRemoteAdapterTestClient"))
        let fm = FileManager.default
        if !fm.fileExists(atPath: files.framework.path) {
            try? fm.removeItem(at: dest)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for (src, dst) in [(script, files.script), (fw, files.framework), (client, files.testClient)] {
                // ditto keeps the framework's symlinks and code signature intact
                guard runProcess("/usr/bin/ditto", [src.path, dst.path]) == 0 else { return nil }
            }
        }
        runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path], timeout: 5)
        // Remove copies left by older versions.
        let parent = dest.deletingLastPathComponent()
        for old in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? [] where old.lastPathComponent != version {
            try? fm.removeItem(at: old)
        }
        return files
    }

    // MARK: Lifecycle

    func start() {
        guard stopped else { return }
        stopped = false
        source = .starting
        Task.detached(priority: .utility) {
            Self.killOrphanedStreams()
            let files = Self.installAdapter()
            let status = files.map { runProcess("/usr/bin/perl", [$0.script.path, $0.framework.path, $0.testClient.path, "test"], timeout: 8) } ?? -1
            await MainActor.run {
                guard !self.stopped else { return }
                self.adapterFiles = files
                if status == 0 {
                    self.startStream()
                } else {
                    log.error("Media adapter test failed (\(status, privacy: .public)); using AppleScript fallback")
                    self.activateFallback()
                }
            }
        }
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        track = nil
        source = .disabled
    }

    // MARK: Adapter stream

    private func startStream() {
        guard let files = adapterFiles else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [files.script.path, files.framework.path, "stream", "--micros", "--debounce=60"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            out.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.streamEnded() }
        }
        do {
            try p.run()
            process = p
            source = .adapter
            payload = [:]
            lineBuffer = Data()
        } catch {
            log.error("Could not launch media adapter: \(error.localizedDescription, privacy: .public)")
            activateFallback()
        }
    }

    private func streamEnded() {
        process = nil
        guard !stopped, source == .adapter else { return }
        let now = Date()
        crashTimes = crashTimes.filter { now.timeIntervalSince($0) < 60 } + [now]
        if crashTimes.count >= 3 {
            log.error("Media adapter crashed 3× in 60 s; switching to AppleScript")
            activateFallback()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.stopped, self.source == .adapter else { return }
                self.startStream()
            }
        }
    }

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let p = obj["payload"] as? [String: Any] else { continue }
            let diff = obj["diff"] as? Bool ?? false
            if diff {
                for (k, v) in p {
                    if v is NSNull { payload.removeValue(forKey: k) } else { payload[k] = v }
                }
            } else {
                payload = p
            }
            applyPayload(artworkChanged: !diff || p.keys.contains("artworkData"))
        }
    }

    private func applyPayload(artworkChanged: Bool) {
        guard let title = payload["title"] as? String, !title.isEmpty else {
            track = nil
            return
        }
        var artwork = track?.artwork
        if artworkChanged {
            if let b64 = payload["artworkData"] as? String, let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                artwork = NSImage(data: data)
            } else {
                artwork = nil
            }
        }
        let payload = self.payload
        let micros = { (k: String) -> Double in (payload[k] as? NSNumber)?.doubleValue ?? 0 }
        let ts = micros("timestampEpochMicros")
        track = NowPlayingTrack(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            duration: micros("durationMicros") / 1_000_000,
            elapsed: micros("elapsedTimeMicros") / 1_000_000,
            timestamp: ts > 0 ? Date(timeIntervalSince1970: ts / 1_000_000) : Date(),
            isPlaying: payload["playing"] as? Bool ?? false,
            rate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1,
            bundleID: payload["bundleIdentifier"] as? String ?? "",
            artwork: artwork
        )
    }

    // MARK: Controls

    func togglePlayPause() {
        if var t = track { // optimistic update; the stream will confirm
            t.elapsed = t.elapsed(at: Date()); t.timestamp = Date(); t.isPlaying.toggle(); track = t
        }
        switch source {
        case .adapter: adapter(["send", "2"])
        case .appleScript: appleScriptCommand("playpause")
        default: break
        }
    }

    func next() {
        switch source {
        case .adapter: adapter(["send", "4"])
        case .appleScript: appleScriptCommand("next track")
        default: break
        }
    }

    func previous() {
        switch source {
        case .adapter: adapter(["send", "5"])
        case .appleScript: appleScriptCommand("previous track")
        default: break
        }
    }

    func seek(to seconds: Double) {
        if var t = track { t.elapsed = seconds; t.timestamp = Date(); track = t }
        switch source {
        case .adapter: adapter(["seek", String(Int64(max(0, seconds) * 1_000_000))])
        case .appleScript: appleScriptCommand("set player position to \(String(format: "%.2f", seconds))")
        default: break
        }
    }

    private func adapter(_ args: [String]) {
        guard let files = adapterFiles else { return }
        Task.detached(priority: .userInitiated) {
            runProcess("/usr/bin/perl", [files.script.path, files.framework.path] + args, timeout: 5)
        }
    }

    // MARK: AppleScript fallback (Music + Spotify)

    private static let players: [(bundleID: String, name: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Music"),
    ]

    private func activateFallback() {
        process?.terminate()
        process = nil
        source = .appleScript
        fallbackTimer?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollAppleScript() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        fallbackTimer = t
        pollAppleScript()
    }

    /// Only talks to players that are already running. `tell application` would launch them otherwise.
    private func runningPlayer() -> (bundleID: String, name: String)? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.players.first { running.contains($0.bundleID) }
    }

    private func pollAppleScript() {
        guard let player = runningPlayer() else { track = nil; return }
        let artworkExpr = player.name == "Spotify" ? "(artwork url of t)" : "\"\""
        let src = """
        tell application "\(player.name)"
            if player state is stopped then return ""
            set t to current track
            set d to duration of t
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (d as text) & linefeed & ((player position) as text) & linefeed & ((player state) as text) & linefeed & \(artworkExpr)
        end tell
        """
        var err: NSDictionary?
        guard let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, !out.isEmpty else {
            track = nil
            return
        }
        let parts = out.components(separatedBy: "\n")
        guard parts.count >= 6 else { return }
        let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        var duration = num(parts[3])
        if player.name == "Spotify" { duration /= 1000 } // Spotify reports milliseconds
        var artwork = track?.title == parts[0] ? track?.artwork : nil
        if parts.count >= 7, !parts[6].isEmpty, parts[6] != artworkURLLoaded, let url = URL(string: parts[6]) {
            artworkURLLoaded = parts[6]
            artwork = nil
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) else { return }
                await MainActor.run { self?.track?.artwork = img }
            }
        }
        track = NowPlayingTrack(title: parts[0], artist: parts[1], album: parts[2], duration: duration,
                                elapsed: num(parts[4]), timestamp: Date(), isPlaying: parts[5] == "playing",
                                rate: 1, bundleID: player.bundleID, artwork: artwork)
    }

    private func appleScriptCommand(_ cmd: String) {
        guard let player = runningPlayer() else { return }
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"\(player.name)\" to \(cmd)")?.executeAndReturnError(&err)
        pollAppleScript()
    }

    /// Sample data for `--snapshot --demo` marketing renders.
    func setDemo(_ t: NowPlayingTrack) { track = t; source = .adapter }
}
