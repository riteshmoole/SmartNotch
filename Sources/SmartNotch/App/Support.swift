import AppKit
import SwiftUI
import os

let log = Logger(subsystem: "com.rick.SmartNotch", category: "app")

enum AppPaths {
    /// ~/Library/Application Support/SmartNotch
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("SmartNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func dir(_ name: String) -> URL {
        let url = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Global actions the SwiftUI layer can trigger without holding a reference to AppKit controllers.
@MainActor
enum AppActions {
    static var openSettings: () -> Void = {}
    static var collapse: () -> Void = {}
    /// Collapses only if the given screen point is outside the open island.
    static var collapseIfOutside: (CGPoint) -> Void = { _ in }
}

extension String {
    /// Strips bidi overrides and control characters so hostile file names or clipboard text
    /// can't reorder or break the UI. Always render the result with `Text(verbatim:)`.
    var displaySafe: String {
        let bidi: ClosedRange<UInt32> = 0x202A...0x202E
        let isolates: ClosedRange<UInt32> = 0x2066...0x2069
        var out = String.UnicodeScalarView()
        for s in unicodeScalars {
            if bidi.contains(s.value) || isolates.contains(s.value) || s.value == 0x200E || s.value == 0x200F { continue }
            if CharacterSet.controlCharacters.contains(s) { out.append(" "); continue }
            out.append(s)
        }
        return String(out)
    }
}

extension Color {
    /// "#RRGGBB" or "#RRGGBBAA".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0x000000FF
        self.init(.sRGB,
                  red: Double((v >> 24) & 0xFF) / 255,
                  green: Double((v >> 16) & 0xFF) / 255,
                  blue: Double((v >> 8) & 0xFF) / 255,
                  opacity: Double(v & 0xFF) / 255)
    }
}

/// Runs a command and returns its exit status; output is discarded.
@discardableResult
func runProcess(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { usleep(20_000) }
    if p.isRunning { p.terminate(); return -2 }
    return p.terminationStatus
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let s = Int(seconds.rounded(.down))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
