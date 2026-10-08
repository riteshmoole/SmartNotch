import AppKit
import Security

/// Installs a newer release over the running app, then relaunches it.
///
/// Files this app downloads itself carry no quarantine flag, so Gatekeeper doesn't stop the new
/// copy and nobody has to click "Open Anyway" again. Because nothing checks it for us, we check it
/// ourselves: the new bundle must satisfy this build's designated requirement (same bundle ID, same
/// signing certificate) and be a higher version. Same requirement also means macOS permission
/// grants carry over.
enum SelfUpdate {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Why the app can't replace itself in place, or nil when it can.
    static var blocker: String? {
        let path = Bundle.main.bundleURL.path
        // Opened straight from Downloads while still quarantined: macOS runs a read-only copy.
        if path.contains("/AppTranslocation/") {
            return "SmartNotch is running from a temporary copy. Move it to Applications first."
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) || !FileManager.default.isWritableFile(atPath: path) {
            return "This Mac account can't change apps in \(parent)."
        }
        return nil
    }

    /// Downloads, checks and swaps in the new version. Returns the URL of the old bundle, now in a
    /// temporary folder, for `relaunch` to delete.
    static func install(from source: URL, currentVersion: String) async throws -> URL {
        let app = Bundle.main.bundleURL
        let fm = FileManager.default
        // On the same volume as the app, so the final swap is a rename.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        do {
            var request = URLRequest(url: source, timeoutInterval: 60)
            request.setValue("SmartNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (tmp, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "The download failed.") }
            let zip = work.appendingPathComponent("SmartNotch.zip")
            try fm.moveItem(at: tmp, to: zip)

            let unpacked = work.appendingPathComponent("new", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            let newApp = unpacked.appendingPathComponent("SmartNotch.app")
            guard fm.fileExists(atPath: newApp.path) else { throw Failure(message: "The download didn't contain SmartNotch.") }

            try verify(newApp, against: app)
            let newVersion = Bundle(url: newApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            guard UpdateChecker.isNewer(newVersion, than: currentVersion) else {
                throw Failure(message: "The download (\(newVersion)) isn't newer than this version.")
            }

            // Two renames: the running app keeps working from its moved bundle until it quits.
            let old = work.appendingPathComponent("old.app")
            try fm.moveItem(at: app, to: old)
            do {
                try fm.moveItem(at: newApp, to: app)
            } catch {
                try? fm.moveItem(at: old, to: app)
                throw error
            }
            try? fm.removeItem(at: zip)
            return work
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }
    }

    /// Opens the new copy once this process has exited, deletes the old copy, then quits.
    @MainActor
    static func relaunch(cleaning work: URL) {
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"; /bin/rm -rf \"$3\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path, work.path]
        do {
            try p.run()
        } catch {
            log.error("Relaunch helper failed: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    private static func verify(_ candidate: URL, against running: URL) throws {
        var current: SecStaticCode?
        var next: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(running as CFURL, [], &current) == errSecSuccess, let current,
              SecCodeCopyDesignatedRequirement(current, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(candidate as CFURL, [], &next) == errSecSuccess, let next else {
            throw Failure(message: "Couldn't check the download's signature.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(next, flags, requirement)
        guard status == errSecSuccess else {
            log.error("Update signature check failed: \(status, privacy: .public)")
            throw Failure(message: "The download isn't signed like this copy of SmartNotch, so it wasn't installed.")
        }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure(message: "Couldn't unpack the download.") }
    }
}
