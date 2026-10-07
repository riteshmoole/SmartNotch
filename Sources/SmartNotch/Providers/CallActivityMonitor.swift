import AppKit
import CoreAudio
import CoreMediaIO

/// "In a call" live activity (PRD D4b), built only on public signals verified in S5:
/// mic or camera is running somewhere, *and* a known conferencing app is running.
/// It can't know caller names or show Messages banners, and it never reads content.
/// The 1.5 s device check runs only while a known call app is open.
@MainActor
final class CallActivityMonitor: ObservableObject {
    @Published private(set) var isInCall = false
    @Published private(set) var appName: String?
    @Published private(set) var micOn = false
    @Published private(set) var cameraOn = false

    /// Our own Mirror tab uses the camera; ignore that.
    var isOwnCameraActive: () -> Bool = { false }

    static let knownApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.apple.FaceTime": "FaceTime",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "Cisco-Systems.Spark": "Webex",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
    ]

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appsChanged() }
            })
        }
        appsChanged()
    }

    func stop() {
        running = false
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate(); timer = nil
        isInCall = false; appName = nil; micOn = false; cameraOn = false
    }

    private func runningCallApp() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, let name = Self.knownApps[id] { return name }
        }
        return nil
    }

    private func appsChanged() {
        if runningCallApp() != nil {
            if timer == nil {
                let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                }
                t.tolerance = 0.5
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        } else {
            timer?.invalidate(); timer = nil
        }
        evaluate()
    }

    private func evaluate() {
        guard let app = runningCallApp() else {
            if isInCall { isInCall = false }
            appName = nil; micOn = false; cameraOn = false
            return
        }
        let mic = Self.anyInputRunning()
        let cam = !isOwnCameraActive() && Self.anyCameraRunning()
        if mic != micOn { micOn = mic }
        if cam != cameraOn { cameraOn = cam }
        let inCall = mic || cam
        if appName != app { appName = app }
        if inCall != isInCall { isInCall = inCall }
    }

    // MARK: Device probes (no permission required; verified in S5)

    nonisolated static func anyInputRunning() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        for id in ids {
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var sSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &sSize)
            guard sSize > 0 else { continue }
            var runningAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                         mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var rSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &runningAddr, 0, nil, &rSize, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    nonisolated static func anyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids)
        for id in ids {
            var ra = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                               mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                               mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &ra, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == noErr, running != 0 { return true }
        }
        return false
    }
}
