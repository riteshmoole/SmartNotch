import AppKit
import IOKit.pwr_mgt

/// Keep Awake through a power-management assertion (shows in `pmset -g assertions`).
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() { set(!isOn) }

    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "SmartNotch Keep Awake" as CFString, &assertionID)
            isOn = r == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertionID)
            isOn = false
        }
    }
}

enum SystemActions {
    static let focusShortcutName = "SmartNotch Focus"

    /// No public API toggles Focus. We run a Shortcut the user creates once.
    /// Returns false when the Shortcut doesn't exist.
    static func toggleFocus() async -> Bool {
        await Task.detached { runProcess("/usr/bin/shortcuts", ["run", focusShortcutName], timeout: 15) == 0 }.value
    }

    @MainActor
    static func showFocusSetupHelp() {
        AppActions.collapse()
        let alert = NSAlert()
        alert.messageText = "Set up Focus toggle"
        alert.informativeText = """
        macOS doesn't let apps switch Focus directly, so SmartNotch runs a Shortcut for you.

        1. Open the Shortcuts app and create a new shortcut.
        2. Add the action "Set Focus" → choose Do Not Disturb → "Toggle".
        3. Name the shortcut exactly: \(focusShortcutName)

        Then press the Focus button again.
        """
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
