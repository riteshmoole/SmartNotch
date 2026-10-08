import SwiftUI

/// Keep Awake, Focus, Mirror and timer presets in one row. Lives under the player on the
/// Now Playing tab (on Utilities when Now Playing is turned off).
struct QuickActionsRow: View {
    @ObservedObject var app: AppState
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var timers: TimerStore
    let theme: Theme
    @ViewState private var focusBusy = false

    var body: some View {
        HStack(spacing: 6) {
            Button { keepAwake.toggle() } label: { Label("Keep Awake", systemImage: "cup.and.saucer.fill") }
                .buttonStyle(PillButtonStyle(tint: theme.accentColor, active: keepAwake.isOn))
                .accessibilityAddTraits(keepAwake.isOn ? .isSelected : [])
            Button {
                guard !focusBusy else { return }
                focusBusy = true
                Task {
                    let ok = await SystemActions.toggleFocus()
                    focusBusy = false
                    if !ok { SystemActions.showFocusSetupHelp() }
                }
            } label: { Label(focusBusy ? "Focus…" : "Focus", systemImage: "moon.fill") }
                .buttonStyle(PillButtonStyle())
            Button { app.activeTab = .mirror } label: { Label("Mirror", systemImage: "camera.fill") }
                .buttonStyle(PillButtonStyle())

            Spacer(minLength: 6)

            Image(systemName: "timer").opacity(0.7).accessibilityHidden(true)
            ForEach([1.0, 5, 10, 25], id: \.self) { m in
                Button("\(Int(m))m") { timers.start(minutes: m) }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityLabel("Start \(Int(m)) minute timer")
            }
            if let t = timers.soonest {
                HStack(spacing: 4) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(verbatim: formatTime(max(0, t.endDate.timeIntervalSince(ctx.date)).rounded(.up))).monospacedDigit()
                    }
                    if timers.timers.count > 1 {
                        Text(verbatim: "+\(timers.timers.count - 1)").opacity(0.6)
                    }
                    Button { timers.cancel(t) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel timer")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(theme.accentColor.opacity(0.25)))
                .fixedSize()
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(.system(size: 11))
        .lineLimit(1)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11))
            configuration.title
        }
    }
}
