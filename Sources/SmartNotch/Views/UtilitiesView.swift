import AVFoundation
import SwiftUI

struct UtilitiesView: View {
    @ObservedObject var app: AppState
    @ObservedObject var stats: SystemStats
    @ObservedObject var settings: Settings
    let theme: Theme

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                StatTile(symbol: "cpu", title: "CPU", value: stats.cpu.map { "\(Int($0 * 100))%" } ?? "—",
                         fraction: stats.cpu, tint: theme.accentColor)
                StatTile(symbol: "memorychip", title: "Memory",
                         value: stats.memUsed.map { String(format: "%.1f / %.0f GB", $0 / 1_073_741_824, stats.memTotal / 1_073_741_824) } ?? "—",
                         fraction: stats.memUsed.map { $0 / stats.memTotal }, tint: theme.accentColor)
                StatTile(symbol: stats.wifi?.isOn == false ? "wifi.slash" : "wifi", title: "Wi-Fi",
                         value: wifiText, fraction: stats.wifi.map { Double($0.bars) / 3 }, tint: theme.accentColor)
            }
            .frame(maxHeight: .infinity)
            // The quick actions normally live on the Now Playing tab; keep them reachable when it's off.
            if !settings.mediaEnabled {
                QuickActionsRow(app: app, keepAwake: app.keepAwake, timers: app.timers, theme: theme)
            }
        }
    }

    private var wifiText: String {
        guard let w = stats.wifi else { return "—" }
        if !w.isOn { return "Off" }
        return w.rssi == 0 ? "Not connected" : "Connected"
    }
}

private struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double?
    let tint: Color
    @Environment(\.notchTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).opacity(0.6)
            Spacer(minLength: 0)
            Text(verbatim: value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            LevelBar(value: fraction ?? 0, tint: tint).frame(height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.foregroundColor.opacity(0.07)))
        .accessibilityElement(children: .combine)
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
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.foregroundColor.opacity(0.1)))
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
