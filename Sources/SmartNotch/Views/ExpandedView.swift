import SwiftUI

struct ExpandedView: View {
    @ObservedObject var app: AppState
    let geometry: NotchGeometry
    let theme: Theme

    private let hPad: CGFloat = 24

    private var topRowHeight: CGFloat { max(geometry.coreSize.height, 28) }
    private var sideWidth: CGFloat {
        (NotchGeometry.expandedSize.width - hPad * 2 - (geometry.hasNotch ? geometry.coreSize.width : 0)) / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBar(app: app, settings: app.settings, theme: theme)
                    .frame(width: sideWidth, alignment: .leading)
                if geometry.hasNotch { Spacer(minLength: geometry.coreSize.width) } else { Spacer(minLength: 0) }
                HeaderStatus(keepAwake: app.keepAwake, updates: app.updates, theme: theme)
                    .frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: topRowHeight)

            Group {
                switch app.activeTab {
                case .media: NowPlayingView(np: app.nowPlaying, volume: app.volume, settings: app.settings, theme: theme)
                case .shelf: ShelfView(shelf: app.shelf, settings: app.settings, theme: theme)
                case .clipboard: ClipboardView(clipboard: app.clipboard, settings: app.settings, theme: theme)
                case .utilities: UtilitiesView(app: app, stats: app.stats, keepAwake: app.keepAwake, timers: app.timers, theme: theme)
                case .mirror: MirrorView(camera: app.camera, theme: theme)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 12)
        }
        .padding(.horizontal, hPad)
        .padding(.bottom, 16)
    }
}

private struct TabBar: View {
    @ObservedObject var app: AppState
    @ObservedObject var settings: Settings
    let theme: Theme

    private var tabs: [NotchTab] {
        NotchTab.allCases.filter { tab in
            switch tab {
            case .media: settings.mediaEnabled
            case .shelf: settings.shelfEnabled
            case .clipboard: settings.clipboardEnabled
            default: true
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button { app.activeTab = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(app.activeTab == tab ? Color.white.opacity(0.16) : .clear)
                        )
                        .foregroundStyle(app.activeTab == tab ? theme.accentColor : theme.foregroundColor.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
    }
}

private struct HeaderStatus: View {
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var updates: UpdateChecker
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            if keepAwake.isOn {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(theme.accentColor)
                    .help("Keep Awake is on")
            }
            Button { AppActions.openSettings(updates.updateAvailable ? .about : nil) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold)) // optically matches the 12 pt tab icons
                    .frame(width: 28, height: 24).contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if updates.updateAvailable {
                            Circle().fill(Color.red)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                                .offset(x: -5, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(updates.updateAvailable ? "Update available: SmartNotch \(updates.latestVersion ?? "")" : "Settings")
            .accessibilityLabel(updates.updateAvailable ? "Settings, update available" : "Settings")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(theme.foregroundColor.opacity(0.75))
    }
}

/// Shared look for the small rounded buttons inside tabs.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .white
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? tint.opacity(0.85) : Color.white.opacity(configuration.isPressed ? 0.22 : 0.1))
            )
            .foregroundStyle(active ? Color.black : Color.white)
            .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22)).opacity(0.6)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).opacity(0.6).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
