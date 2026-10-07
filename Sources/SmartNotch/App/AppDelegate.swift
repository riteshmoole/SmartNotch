import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    private var notchManager: NotchManager!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private let settingsNav = SettingsNavigation()
    private var onboardingWindow: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []
    private var updateItem: NSMenuItem?
    private var updateSeparator: NSMenuItem?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
        notchManager = NotchManager(state: state)
        AppActions.openSettings = { [weak self] tab in self?.showSettings(tab) }
        AppActions.collapse = { [weak self] in self?.notchManager.collapse() }
        AppActions.collapseIfOutside = { [weak self] p in self?.notchManager.collapseIfOutside(p) }

        // ⌃⌥Space toggles the island, so hover is never the only way in.
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.notchManager.toggle()
        }
        if hotKey == nil { log.error("Global hotkey registration failed") }

        // `kill`/logout sends SIGTERM, which skips applicationWillTerminate. Shut the helper down cleanly.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.state.stop()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }

        setUpStatusItem()
        if !state.settings.hasCompletedOnboarding { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.portrait.tophalf.filled", accessibilityDescription: "SmartNotch")
            ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "SmartNotch")
        let menu = NSMenu()
        let update = item("Update Available…", #selector(showUpdate))
        let updateSep = NSMenuItem.separator()
        update.isHidden = true; updateSep.isHidden = true
        menu.addItem(update)
        menu.addItem(updateSep)
        updateItem = update; updateSeparator = updateSep
        menu.addItem(item("Open SmartNotch", #selector(toggleNotch), key: " ", mods: [.control, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Clear Shelf", #selector(clearShelf)))
        menu.addItem(item("Clear Clipboard History", #selector(clearClipboard)))
        menu.addItem(.separator())
        menu.addItem(item("About SmartNotch", #selector(about)))
        menu.addItem(item("Quit SmartNotch", #selector(quit), key: "q"))
        statusItem.menu = menu

        state.updates.$latestVersion.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshUpdateItem()
        }.store(in: &bag)
    }

    private func refreshUpdateItem() {
        let u = state.updates
        updateItem?.isHidden = !u.updateAvailable
        updateSeparator?.isHidden = !u.updateAvailable
        updateItem?.title = "Update Available: SmartNotch \(u.latestVersion ?? "")…"
    }

    private func item(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        return i
    }

    @objc private func toggleNotch() { notchManager.toggle() }
    @objc private func openSettings() { showSettings() }
    @objc private func showUpdate() { showSettings(.about) }
    @objc private func clearShelf() { state.shelf.clear() }
    @objc private func clearClipboard() { state.clipboard.clear() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "A Dynamic Island-style notch for your Mac.\nFree and open source (MIT). Uses mediaremote-adapter (BSD-3-Clause)."),
        ])
    }

    // MARK: Windows

    func showSettings(_ tab: SettingsTab? = nil) {
        notchManager.collapse()
        if let tab { settingsNav.tab = tab }
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "SmartNotch Settings", size: NSSize(width: 560, height: 480),
                                        root: SettingsView(state: state, settings: state.settings, themes: state.themes, nav: settingsNav))
        }
        present(settingsWindow!)
    }

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.state.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
        }
        onboardingWindow = makeWindow(title: "Welcome to SmartNotch", size: NSSize(width: 520, height: 520), root: view)
        present(onboardingWindow!)
    }

    private func makeWindow<V: View>(title: String, size: NSSize, root: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        return w
    }

    private func present(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message when registration fails (common for unsigned apps outside /Applications).
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            log.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
