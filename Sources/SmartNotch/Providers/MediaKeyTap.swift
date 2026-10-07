import AppKit
import ApplicationServices

/// HUD replacement (beta, off by default). An event tap consumes the volume keys, sets the volume
/// ourselves, and shows our HUD in the notch. Needs Accessibility: the TCC permission that lets
/// an app watch or alter input meant for other apps. Testing verified the native HUD stays hidden.
@MainActor
final class MediaKeyTap: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isActive = false

    weak var volume: VolumeController?
    var onHUD: ((HUDKind) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var trustPoll: Timer?
    private var wanted = false

    private enum Key: Int { case volumeUp = 0, volumeDown = 1, mute = 7 }

    func setEnabled(_ on: Bool) {
        wanted = on
        if on { enable() } else { disable() }
    }

    /// Shows the system Accessibility prompt.
    func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(opts)
    }

    private func enable() {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else {
            requestTrust()
            // Wait for the user to flip the switch in System Settings, then start.
            trustPoll?.invalidate()
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isTrusted = AXIsProcessTrusted()
                    if self.isTrusted || !self.wanted {
                        self.trustPoll?.invalidate(); self.trustPoll = nil
                        if self.isTrusted && self.wanted { self.enable() }
                    }
                }
            }
            return
        }
        guard tap == nil else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED: media/volume/brightness keys
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: mediaKeyCallback, userInfo: refcon) else {
            log.error("Event tap creation failed")
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        isActive = true
    }

    private func disable() {
        trustPoll?.invalidate(); trustPoll = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        isActive = false
    }

    fileprivate func reenable() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    /// Returns true when the event was handled and must be swallowed.
    fileprivate func handle(_ event: NSEvent) -> Bool {
        guard event.subtype.rawValue == 8 else { return false }
        let code = (event.data1 & 0xFFFF_0000) >> 16
        let flags = event.data1 & 0xFFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0x0A
        guard let key = Key(rawValue: code), let volume, volume.canSet else { return false }
        guard isDown else { return true } // swallow key-up too, or the system shows its HUD

        let fine = event.modifierFlags.contains([.option, .shift])
        switch key {
        case .volumeUp: volume.step(by: fine ? 1 / 64 : 1 / 16)
        case .volumeDown: volume.step(by: fine ? -1 / 64 : -1 / 16)
        case .mute: volume.setMuted(!volume.isMuted)
        }
        onHUD?(.volume(level: volume.volume, muted: volume.isMuted))
        return true
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
    // The tap runs on the main run loop, so main-actor access is safe here.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { me.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
    let consumed = MainActor.assumeIsolated { me.handle(ns) }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
