import AVFoundation
import SwiftUI

struct UtilitiesView: View {
    @ObservedObject var app: AppState
    @ObservedObject var stats: SystemStats
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var timers: TimerStore
    let theme: Theme
    @ViewState private var focusBusy = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                StatTile(symbol: "cpu", title: "CPU", value: stats.cpu.map { "\(Int($0 * 100))%" } ?? "—",
                         fraction: stats.cpu, tint: theme.accentColor)
                StatTile(symbol: "memorychip", title: "Memory",
                         value: stats.memUsed.map { String(format: "%.1f / %.0f GB", $0 / 1_073_741_824, stats.memTotal / 1_073_741_824) } ?? "—",
                         fraction: stats.memUsed.map { $0 / stats.memTotal }, tint: theme.accentColor)
                StatTile(symbol: stats.wifi?.isOn == false ? "wifi.slash" : "wifi", title: "Wi-Fi",
                         value: wifiText, fraction: stats.wifi.map { Double($0.bars) / 3 }, tint: theme.accentColor)
            }
            HStack(spacing: 8) {
                ActionTile(symbol: "cup.and.saucer.fill", title: "Keep Awake", active: keepAwake.isOn, tint: theme.accentColor) {
                    keepAwake.toggle()
                }
                ActionTile(symbol: "moon.fill", title: focusBusy ? "Focus…" : "Focus", active: false, tint: theme.accentColor) {
                    guard !focusBusy else { return }
                    focusBusy = true
                    Task {
                        let ok = await SystemActions.toggleFocus()
                        focusBusy = false
                        if !ok { SystemActions.showFocusSetupHelp() }
                    }
                }
                ActionTile(symbol: "lock.fill", title: "Lock", active: false, tint: theme.accentColor) {
                    SystemActions.lockScreen()
                }
                ActionTile(symbol: "camera.fill", title: "Mirror", active: false, tint: theme.accentColor) {
                    app.activeTab = .mirror
                }
            }
            timerRow
        }
    }

    private var wifiText: String {
        guard let w = stats.wifi else { return "—" }
        if !w.isOn { return "Off" }
        return w.rssi == 0 ? "Not connected" : "Connected"
    }

    private var timerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer").opacity(0.7)
            ForEach([1.0, 5, 10, 25], id: \.self) { m in
                Button("\(Int(m))m") { timers.start(minutes: m) }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityLabel("Start \(Int(m)) minute timer")
            }
            Spacer(minLength: 4)
            ForEach(timers.timers.sorted { $0.endDate < $1.endDate }.prefix(2)) { t in
                HStack(spacing: 4) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(verbatim: formatTime(max(0, t.endDate.timeIntervalSince(ctx.date)).rounded(.up))).monospacedDigit()
                    }
                    Button { timers.cancel(t) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel timer")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(theme.accentColor.opacity(0.25)))
            }
        }
        .font(.system(size: 11))
    }
}

private struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold)).opacity(0.6)
            Text(verbatim: value).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            LevelBar(value: fraction ?? 0, tint: tint).frame(height: 3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}

private struct ActionTile: View {
    let symbol: String
    let title: String
    let active: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? tint.opacity(0.85) : .white.opacity(0.08)))
            .foregroundStyle(active ? Color.black : Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct MirrorView: View {
    @ObservedObject var camera: CameraPreview
    let theme: Theme

    var body: some View {
        switch camera.status {
        case .denied:
            VStack(spacing: 8) {
                EmptyStateView(symbol: "camera.fill", title: "Camera access is off",
                               detail: "Allow SmartNotch in System Settings → Privacy & Security → Camera.")
                Button("Open Settings") { camera.openPrivacySettings() }.buttonStyle(PillButtonStyle())
            }
        case .noCamera:
            EmptyStateView(symbol: "video.slash", title: "No camera found", detail: "")
        default:
            HStack(spacing: 14) {
                CameraLayerView(session: camera.session)
                    .frame(width: 240, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 6) {
                    Label("Mirror", systemImage: "camera.fill").font(.system(size: 13, weight: .semibold))
                    Text("Check yourself before a call. The camera turns off as soon as the notch closes. Nothing is recorded.")
                        .font(.system(size: 11)).opacity(0.6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CameraLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    final class LayerView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            preview.frame = bounds
            if let c = preview.connection, c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = true
            }
        }
    }

    func makeNSView(context: Context) -> LayerView {
        let v = LayerView()
        v.preview.session = session
        return v
    }

    func updateNSView(_ nsView: LayerView, context: Context) {}
}
