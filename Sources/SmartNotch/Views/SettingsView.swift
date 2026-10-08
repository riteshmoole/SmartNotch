import SwiftUI

enum SettingsTab: Hashable {
    case general, modules, appearance, about
}

/// Which Settings tab is showing, so the notch's gear can open straight to About when an update is waiting.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    let state: AppState
    @ObservedObject var settings: Settings
    @ObservedObject var themes: ThemeStore
    @ObservedObject var nav: SettingsNavigation

    var body: some View {
        TabView(selection: $nav.tab) {
            GeneralSettings(settings: settings, updates: state.updates)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ModuleSettings(settings: settings, mediaKeys: state.mediaKeys, nowPlaying: state.nowPlaying, call: state.call, clipboard: state.clipboard)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.modules)
            AppearanceSettings(settings: settings, themes: themes)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            AboutSettings(updates: state.updates, settings: settings)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(16)
        .frame(width: 560, height: 480)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: Settings
    @ObservedObject var updates: UpdateChecker
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Open when hovering over the notch", isOn: $settings.hoverToOpen)
                if settings.hoverToOpen {
                    LabeledContent("Hover delay") {
                        Slider(value: $settings.hoverDelay, in: 0.05...0.8, step: 0.05) {
                            EmptyView()
                        } minimumValueLabel: { Text("Fast") } maximumValueLabel: { Text("Slow") }
                    }
                }
                LabeledContent("Keyboard shortcut", value: "⌃⌥Space")
                Text("You can always click the notch, or use the shortcut, to open it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Displays") {
                Toggle("Show a floating pill on screens without a notch", isOn: $settings.showPillOnNotchless)
                Toggle("Use the floating pill on every screen (also notched ones)", isOn: $settings.forcePill)
                Toggle("Show live activities beside the notch (music, timers, calls)", isOn: $settings.showWings)
                Toggle("Show an animation when you plug in or unplug the charger", isOn: $settings.chargingAnimation)
                Toggle("Hide SmartNotch from screen sharing and recordings", isOn: $settings.hideFromScreenShare)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        loginError = LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let loginError {
                    Text("Couldn't change this automatically (\(loginError)). Add SmartNotch in System Settings → General → Login Items instead.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !UpdateChecker.repository.isEmpty {
                    Toggle("Check for updates once a day", isOn: $settings.checkForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModuleSettings: View {
    @ObservedObject var settings: Settings
    @ObservedObject var mediaKeys: MediaKeyTap
    @ObservedObject var nowPlaying: NowPlayingProvider
    @ObservedObject var call: CallActivityMonitor
    let clipboard: ClipboardMonitor
    @ViewState private var excludedText = ""

    var body: some View {
        Form {
            Section("Now Playing") {
                Toggle("Now Playing", isOn: $settings.mediaEnabled)
                Text(sourceDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section("File Shelf") {
                Toggle("File shelf (drag files onto the notch)", isOn: $settings.shelfEnabled)
                Picker("Auto-clear shelf after", selection: $settings.shelfAutoClearHours) {
                    Text("1 hour").tag(1); Text("8 hours").tag(8); Text("24 hours").tag(24)
                    Text("1 week").tag(168); Text("Never").tag(0)
                }
            }
            Section("Clipboard History") {
                Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
                Toggle("Remember text history after quitting (saved on this Mac)", isOn: $settings.clipboardPersist)
                    .onChange(of: settings.clipboardPersist) { _, on in clipboard.persistenceChanged(on) }
                VStack(alignment: .leading) {
                    Text("Never record copies from these apps (bundle IDs, one per line):").font(.caption)
                    TextEditor(text: $excludedText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 70)
                        .onAppear { excludedText = settings.clipboardExcludedApps.joined(separator: "\n") }
                        .onChange(of: excludedText) { _, t in
                            settings.clipboardExcludedApps = t.split(whereSeparator: \.isNewline)
                                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        }
                }
                Text("Items that password managers mark as concealed are always skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Calls") {
                Toggle("Show “In a call” when Zoom, FaceTime, Phone… use your mic or camera", isOn: $settings.callActivityEnabled)
                Text("Shows once a call is answered (macOS doesn't tell apps about ringing calls). Works with \(CallActivityMonitor.knownAppNames). Uses only whether the mic/camera is busy. SmartNotch never sees who you're talking to.")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.callActivityEnabled {
                    Text(callStatus).font(.caption).foregroundStyle(call.isInCall ? .green : .secondary)
                }
            }
            Section("Volume HUD") {
                Toggle("Replace the macOS volume overlay with SmartNotch's", isOn: $settings.hudReplacement)
                if settings.hudReplacement && !mediaKeys.isTrusted {
                    HStack {
                        Text("Needs Accessibility permission so SmartNotch can catch the volume keys.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Grant…") { mediaKeys.requestTrust() }
                    }
                } else {
                    Text("Needs Accessibility permission. Outputs without software volume (some HDMI displays) keep the normal behavior.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Live status, so "it doesn't show my call" can be narrowed down to the app or the mic.
    private var callStatus: String {
        guard let app = call.appName else { return "Status: none of the apps above is open." }
        let devices = "mic \(call.micOn ? "in use" : "idle"), camera \(call.cameraOn ? "in use" : "idle")"
        return call.isInCall ? "Status: in a call on \(app) (\(devices))." : "Status: \(app) is open, \(devices). Waiting for a call."
    }

    private var sourceDescription: String {
        switch nowPlaying.source {
        case .adapter: "Status: working with every player, including browsers."
        case .appleScript: "Status: limited mode. Only Music and Spotify are supported on this macOS version (macOS will ask for permission to control them)."
        case .starting: "Status: starting…"
        case .disabled: "Status: off"
        }
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var settings: Settings
    @ObservedObject var themes: ThemeStore

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                    ForEach(themes.themes) { t in
                        Button { settings.themeID = t.id } label: {
                            VStack(spacing: 6) {
                                Capsule().fill(t.backgroundColor)
                                    .frame(width: 90, height: 26)
                                    .overlay(Circle().fill(t.accentColor).frame(width: 10, height: 10))
                                    .shadow(color: t.glow ? t.glowSwiftColor.opacity(0.8) : .clear, radius: 6)
                                Text(t.name).font(.caption)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .stroke(settings.themeID == t.id ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Toggle("Glow around the open notch (themes that support it)", isOn: $settings.glowEnabled)
                if themes.current.isGlass {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $settings.glassFrost, in: 0...1) {
                            Text("Glass clarity")
                        } minimumValueLabel: {
                            Text("Clear").font(.caption)
                        } maximumValueLabel: {
                            Text("Frosted").font(.caption)
                        }
                        Text("Clearer glass shows more of what's behind the notch, but text can be harder to read over busy windows. Hover the notch to preview. While open, glass themes hold keyboard focus (macOS only draws clear glass in the focused window); moving away or pressing Esc gives it back.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Custom themes") {
                Text("Themes are small JSON files. Drop your own into the folder below, then click Reload.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Themes Folder") { NSWorkspace.shared.open(ThemeStore.userThemesDir) }
                    Button("Reload") { themes.reload() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var settings: Settings

    var body: some View {
        ScrollView {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("SmartNotch").font(.title2.bold())
            Text("Version \(updates.currentVersion)").foregroundStyle(.secondary)
            if !UpdateChecker.repository.isEmpty {
                if updates.updateAvailable {
                    UpdateCard(updates: updates)
                } else if settings.checkForUpdates {
                    UpdateStatusLine(updates: updates)
                }
            }
            Text("A Dynamic Island-style notch for your Mac.\nFree and open source under the MIT License.")
                .multilineTextAlignment(.center).font(.callout)
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy").font(.headline)
                Text("Everything stays on your Mac. No accounts, no analytics, no tracking. Clipboard history lives in memory unless you choose to save it. The camera only runs while the Mirror tab is open. The only network request is the daily update check, which you can turn off in General.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Third-party").font(.headline).padding(.top, 4)
                Text("mediaremote-adapter © Jonas van den Berg and contributors, BSD 3-Clause License.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        }
    }
}

private struct UpdateCard: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SmartNotch \(updates.latestVersion ?? "") is available", systemImage: "arrow.down.circle.fill")
                .font(.headline).foregroundStyle(Color.accentColor)
            if let summary = updates.releaseSummary {
                Text(verbatim: summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text("To update: click Download, quit SmartNotch, then drag the new SmartNotch from Downloads into Applications and choose Replace. Your settings and permissions carry over.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Download") { NSWorkspace.shared.open(UpdateChecker.downloadURL) }
                    .buttonStyle(.borderedProminent)
                if let url = updates.releaseURL {
                    Link("What's new", destination: url)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)))
    }
}

private struct UpdateStatusLine: View {
    @ObservedObject var updates: UpdateChecker

    private var status: String {
        if updates.isChecking { return "Checking for updates…" }
        if updates.lastCheckFailed { return "Couldn't check for updates." }
        if updates.lastChecked != nil { return "You're up to date." }
        return ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(status).font(.caption).foregroundStyle(.secondary)
            Button("Check Now") { updates.check() }
                .controlSize(.small)
                .disabled(updates.isChecking)
        }
    }
}
