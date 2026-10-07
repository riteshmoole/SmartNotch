import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar agent: no Dock icon
// Kept at top level: NSApplication.delegate is weak.
let delegate: AppDelegate? = MainActor.assumeIsolated { Snapshot.runIfRequested() ? nil : AppDelegate() }
app.delegate = delegate
app.run()
