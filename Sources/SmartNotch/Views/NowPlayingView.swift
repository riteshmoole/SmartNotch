import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var np: NowPlayingProvider
    @ObservedObject var volume: VolumeController
    @ObservedObject var settings: Settings
    let theme: Theme

    @ViewState private var scrubValue: Double?

    var body: some View {
        if !settings.mediaEnabled {
            EmptyStateView(symbol: "music.note", title: "Now Playing is off", detail: "Turn it on in Settings → Modules.")
        } else if let t = np.track {
            player(t)
        } else {
            switch np.source {
            case .starting:
                EmptyStateView(symbol: "music.note", title: "Looking for media…", detail: "")
            case .appleScript:
                EmptyStateView(symbol: "music.note.list", title: "Nothing playing in Music or Spotify",
                               detail: "Full media detection isn't available on this macOS version,\nso SmartNotch can only see Music and Spotify.")
            default:
                EmptyStateView(symbol: "music.note", title: "Nothing playing",
                               detail: "Play something in Music, Spotify, or your browser.")
            }
        }
    }

    private func player(_ t: NowPlayingTrack) -> some View {
        HStack(alignment: .center, spacing: 16) {
            artwork(t)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: t.title.displaySafe).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(verbatim: [t.artist, t.album].filter { !$0.isEmpty }.joined(separator: " — ").displaySafe)
                            .font(.system(size: 12)).opacity(0.65).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VisualizerBars(isPlaying: t.isPlaying, tint: theme.accentColor, bars: 5)
                        .frame(width: 26, height: 18)
                }
                scrubber(t)
                HStack(spacing: 22) {
                    Spacer(minLength: 0)
                    control("backward.fill", label: "Previous") { np.previous() }
                    control(t.isPlaying ? "pause.fill" : "play.fill", size: 22, label: t.isPlaying ? "Pause" : "Play") { np.togglePlayPause() }
                    control("forward.fill", label: "Next") { np.next() }
                    Spacer(minLength: 0)
                }
                volumeRow
            }
        }
    }

    private func artwork(_ t: NowPlayingTrack) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.foregroundColor.opacity(0.08))
            if let art = t.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 34)).opacity(0.4)
            }
        }
        .frame(width: 128, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: t.appName.displaySafe)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(6)
        }
        .accessibilityHidden(true)
    }

    private func scrubber(_ t: NowPlayingTrack) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let elapsed = scrubValue ?? t.elapsed(at: ctx.date)
            let canSeek = t.duration > 0
            VStack(spacing: 2) {
                Slider(value: Binding(get: { elapsed }, set: { scrubValue = $0 }),
                       in: 0...max(t.duration, 1)) { editing in
                    if !editing, let v = scrubValue {
                        np.seek(to: v)
                        scrubValue = nil
                    }
                }
                .controlSize(.mini)
                .tint(theme.accentColor)
                .disabled(!canSeek)
                .accessibilityLabel("Playback position")
                HStack {
                    Text(verbatim: formatTime(elapsed))
                    Spacer()
                    Text(verbatim: canSeek ? "-" + formatTime(max(0, t.duration - elapsed)) : "LIVE")
                }
                .font(.system(size: 9, weight: .medium)).monospacedDigit().opacity(0.55)
            }
        }
    }

    @ViewBuilder private var volumeRow: some View {
        if volume.canSet {
            HStack(spacing: 8) {
                Button { volume.setMuted(!volume.isMuted) } label: {
                    Image(systemName: CollapsedWingsView.speakerSymbol(level: volume.volume, muted: volume.isMuted))
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(volume.isMuted ? "Unmute" : "Mute")
                Slider(value: Binding(get: { Double(volume.volume) }, set: { volume.set(Float($0)) }), in: 0...1)
                    .controlSize(.mini)
                    .tint(theme.foregroundColor.opacity(0.8))
                    .accessibilityLabel("Volume")
            }
            .font(.system(size: 10))
            .opacity(0.8)
        }
    }

    private func control(_ symbol: String, size: CGFloat = 15, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
