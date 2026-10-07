import SwiftUI

/// Live activity shown beside the notch while collapsed (Dynamic Island-style "compact" view).
struct CollapsedWingsView: View {
    @ObservedObject var app: AppState
    @ObservedObject var nowPlaying: NowPlayingProvider
    @ObservedObject var timers: TimerStore
    @ObservedObject var call: CallActivityMonitor
    let geometry: NotchGeometry
    let theme: Theme

    var body: some View {
        let wing = app.activity.wingWidth
        HStack(spacing: 0) {
            leading.frame(width: wing, height: geometry.coreSize.height)
            Spacer(minLength: geometry.coreSize.width)
            trailing.frame(width: wing, height: geometry.coreSize.height)
        }
        .padding(.horizontal, geometry.flare)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .opacity(wing > 0 ? 1 : 0)
    }

    @ViewBuilder private var leading: some View {
        switch app.activity {
        case .hud:
            if case .volume(let level, let muted) = app.hud {
                Image(systemName: Self.speakerSymbol(level: level, muted: muted))
                    .font(.system(size: 13, weight: .semibold))
            }
        case .call:
            HStack(spacing: 4) {
                Circle().fill(call.cameraOn ? Color.green : Color.orange).frame(width: 7, height: 7)
                Image(systemName: call.cameraOn ? "video.fill" : "mic.fill").font(.system(size: 11))
            }
        case .timer:
            Image(systemName: timers.finished != nil ? "bell.fill" : "timer")
                .foregroundStyle(theme.accentColor)
        case .media:
            Group {
                if let art = nowPlaying.track?.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 11))
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch app.activity {
        case .hud:
            if case .volume(let level, let muted) = app.hud {
                LevelBar(value: muted ? 0 : Double(level), tint: theme.accentColor)
                    .frame(width: 46, height: 5)
            }
        case .call:
            Text(verbatim: call.appName ?? "Call").lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.green)
        case .timer:
            if let t = timers.soonest {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(verbatim: formatTime(max(0, t.endDate.timeIntervalSince(ctx.date)).rounded(.up)))
                        .monospacedDigit()
                }
            } else {
                Text("Done").foregroundStyle(theme.accentColor)
            }
        case .media:
            VisualizerBars(isPlaying: nowPlaying.track?.isPlaying == true, tint: theme.accentColor, bars: 4)
                .frame(width: 18, height: 14)
        case .none:
            EmptyView()
        }
    }

    static func speakerSymbol(level: Float, muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        return level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

struct LevelBar: View {
    var value: Double
    var tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(tint).frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

/// Animated from play state only (no audio capture). TimelineView stops ticking when off-screen
/// or paused, so it costs nothing while hidden.
struct VisualizerBars: View {
    var isPlaying: Bool
    var tint: Color
    var bars: Int = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<bars, id: \.self) { i in
                        let phase = t * (3.1 + Double(i) * 0.9) + Double(i) * 1.7
                        let h = isPlaying ? 0.3 + 0.7 * abs(sin(phase) * cos(phase * 0.37)) : 0.18
                        Capsule().fill(tint)
                            .frame(width: max(2, (geo.size.width - CGFloat(bars - 1) * 2) / CGFloat(bars)),
                                   height: max(2, geo.size.height * h))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}
