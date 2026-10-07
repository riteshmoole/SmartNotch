import AppKit
import SwiftUI

/// Debug aid, renders the island offscreen to PNGs and exits. Needs no Screen Recording permission
/// and never touches the mouse.
///   SmartNotch --snapshot <dir>          every state with whatever live data is present
///   SmartNotch --snapshot <dir> --demo   clean sample data, transparent background, cropped to the
///                                        island (used for README / download-page screenshots)
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let demo = args.contains("--demo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            demo ? renderDemo(to: dir) : render(to: dir)
            exit(0)
        }
        return true
    }

    // MARK: Live-data renders

    private static func render(to dir: URL) {
        let state = AppState.shared
        guard let screen = NSScreen.main else { return }
        for (name, g) in [("notch", NotchGeometry.make(for: screen, forcePill: false)),
                          ("pill", NotchGeometry.make(for: screen, forcePill: true))] {
            let vm = NotchViewModel(geometry: g)
            shoot(vm, state, dir.appendingPathComponent("\(name)-collapsed.png"), background: Color(white: 0.55))
            vm.isExpanded = true
            for tab in NotchTab.allCases where tab != .mirror {
                state.activeTab = tab
                shoot(vm, state, dir.appendingPathComponent("\(name)-\(tab.rawValue).png"), background: Color(white: 0.55))
                if name == "pill" { break }
            }
        }
    }

    // MARK: Demo renders

    private static func renderDemo(to dir: URL) {
        let state = AppState.shared
        guard let screen = NSScreen.main else { return }
        let g = NotchGeometry.make(for: screen, forcePill: false)
        seedDemoData(state)

        let vm = NotchViewModel(geometry: g)
        vm.isExpanded = true
        for tab in [NotchTab.media, .shelf, .clipboard, .utilities] {
            if tab == .utilities { state.timers.start(minutes: 10) }
            state.activeTab = tab
            shoot(vm, state, dir.appendingPathComponent("\(tab.rawValue).png"), crop: g.expandedRect.insetBy(dx: -14, dy: -14))
        }

        vm.isExpanded = false
        state.timers.timers.forEach(state.timers.cancel)
        let wingCrop = g.collapsedRect(wing: CollapsedActivity.hud.wingWidth).insetBy(dx: -24, dy: -10)
        state.recomputeActivity()
        settle()
        shoot(vm, state, dir.appendingPathComponent("wings-media.png"), crop: wingCrop)

        state.timers.start(minutes: 25)
        state.recomputeActivity()
        settle()
        shoot(vm, state, dir.appendingPathComponent("wings-timer.png"), crop: wingCrop)

        state.showCharging(PowerFlash(battery: BatteryInfo(percent: 72, isCharging: true, onAC: true), pluggedIn: true))
        state.recomputeActivity()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        shoot(vm, state, dir.appendingPathComponent("wings-charging-start.png"), crop: g.collapsedRect(wing: CollapsedActivity.charging.wingWidth).insetBy(dx: -24, dy: -16))
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        shoot(vm, state, dir.appendingPathComponent("wings-charging.png"), crop: g.collapsedRect(wing: CollapsedActivity.charging.wingWidth).insetBy(dx: -24, dy: -16))
        RunLoop.main.run(until: Date().addingTimeInterval(2.6)) // let the flash end
        state.showCharging(PowerFlash(battery: BatteryInfo(percent: 72, isCharging: false, onAC: false), pluggedIn: false))
        state.recomputeActivity()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        shoot(vm, state, dir.appendingPathComponent("wings-unplugged.png"), crop: g.collapsedRect(wing: CollapsedActivity.charging.wingWidth).insetBy(dx: -24, dy: -16))
        RunLoop.main.run(until: Date().addingTimeInterval(1.9))

        state.showHUD(.volume(level: 0.56, muted: false))
        state.recomputeActivity()
        settle()
        shoot(vm, state, dir.appendingPathComponent("wings-volume.png"), crop: wingCrop)
    }

    private static func seedDemoData(_ state: AppState) {
        state.nowPlaying.setDemo(NowPlayingTrack(
            title: "Midnight Drive", artist: "The Notches", album: "Island Sessions",
            duration: 214, elapsed: 83, timestamp: Date(), isPlaying: true, rate: 1,
            bundleID: "com.apple.Music", artwork: demoArtwork()))

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SmartNotchDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let names = ["Trip Itinerary.pdf", "Poster Final.png", "Lecture 6 Notes.md", "Budget 2026.xlsx", "Demo Clip.mov"]
        state.shelf.setDemo(names.map { name in
            let url = tmp.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("demo".utf8))
            return ShelfItem(id: UUID(), url: url, originalPath: url.path, name: name, addedAt: Date(), isReference: false)
        })

        let now = Date()
        state.clipboard.setDemo([
            ClipItem(content: .text("https://github.com/riteshmoole/SmartNotch"), date: now.addingTimeInterval(-20), sourceBundleID: "com.apple.Safari"),
            ClipItem(content: .image(demoArtwork()), date: now.addingTimeInterval(-95), sourceBundleID: "com.apple.Preview"),
            ClipItem(content: .text("Meeting moved to 3:30, same Zoom link"), date: now.addingTimeInterval(-300), sourceBundleID: "com.apple.MobileSMS"),
            ClipItem(content: .text("let island = NotchShape(flare: 14, bottomRadius: 28)"), date: now.addingTimeInterval(-900), sourceBundleID: "com.apple.dt.Xcode"),
            ClipItem(content: .text("Oat milk, coffee beans, bananas, basil"), date: now.addingTimeInterval(-3600), sourceBundleID: "com.apple.Notes"),
        ])

        state.stats.setDemo(cpu: 0.12, memUsed: 9.4 * 1_073_741_824, wifi: WiFiInfo(isOn: true, rssi: -48))
    }

    /// Original abstract cover art: a warm gradient with a soft "sun".
    private static func demoArtwork() -> NSImage {
        let size = NSSize(width: 400, height: 400)
        return NSImage(size: size, flipped: false) { r in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.45, blue: 0.25, alpha: 1),
                                NSColor(red: 0.55, green: 0.2, blue: 0.75, alpha: 1),
                                NSColor(red: 0.1, green: 0.1, blue: 0.35, alpha: 1)])!.draw(in: r, angle: -70)
            NSColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 130, y: 150, width: 140, height: 140)).fill()
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 150)).fill()
            return true
        }
    }

    // MARK: Rendering

    private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    /// - Parameter crop: optional rect in *screen* coordinates (same space as NotchGeometry rects).
    private static func shoot(_ vm: NotchViewModel, _ state: AppState, _ file: URL,
                              background: Color = .clear, crop: CGRect? = nil) {
        let g = vm.geometry
        let size = g.panelFrame.size
        let host = NSHostingView(rootView: NotchRootView(vm: vm, app: state, settings: state.settings, themes: state.themes)
            .background(background))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.7)) // let animations settle
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        var out: NSBitmapImageRep = rep
        if let crop, let cg = rep.cgImage {
            // screen rect → view coords (view origin = panel origin, y up) → pixel rect (y down)
            let scale = CGFloat(rep.pixelsWide) / size.width
            let local = CGRect(x: crop.minX - g.panelFrame.minX, y: crop.minY - g.panelFrame.minY,
                               width: crop.width, height: crop.height).intersection(CGRect(origin: .zero, size: size))
            let px = CGRect(x: local.minX * scale, y: (size.height - local.maxY) * scale,
                            width: local.width * scale, height: local.height * scale)
            if let c = cg.cropping(to: px) { out = NSBitmapImageRep(cgImage: c) }
        }
        try? out.representation(using: .png, properties: [:])?.write(to: file)
    }
}
