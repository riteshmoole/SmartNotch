@preconcurrency import AVFoundation
import AppKit

/// Mirror tab. The capture session runs only while the tab is visible in an expanded notch, and
/// stops the moment it collapses or the tab changes. Frames go straight to a preview layer and
/// are never written anywhere.
@MainActor
final class CameraPreview: ObservableObject {
    enum Status: Equatable { case idle, running, denied, noCamera }

    @Published private(set) var status: Status = .idle
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "SmartNotch.camera")
    private var configured = false
    private var wanted = false

    var isRunning: Bool { status == .running }

    func setActive(_ on: Bool) {
        wanted = on
        on ? start() : stop()
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { if self.wanted { self.run() } } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    private func run() {
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                status = .noCamera
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .medium
            session.addInput(input)
            session.commitConfiguration()
            configured = true
        }
        let s = session
        queue.async { if !s.isRunning { s.startRunning() } }
        status = .running
    }

    private func stop() {
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
        if status == .running { status = .idle }
    }

    func openPrivacySettings() {
        AppActions.collapse()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
