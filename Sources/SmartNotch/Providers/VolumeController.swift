import AudioToolbox
import CoreAudio
import Foundation

/// Reads and sets the default output device's volume through CoreAudio. `canSet` is false for
/// outputs with no software volume (e.g. many HDMI/DisplayPort displays). Callers must then leave
/// hardware keys alone.
///
/// Uses the virtual main volume when the device has one, else the device's own per-channel
/// volume scalars (some USB and display outputs only expose those).
@MainActor
final class VolumeController: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var canSet = false
    /// Name of the current output, for the status line in Settings.
    @Published private(set) var deviceName: String?

    private enum Control: Equatable {
        case none, main
        /// Per-channel `kAudioDevicePropertyVolumeScalar` on these elements (0 = main).
        case channels([UInt32])
    }

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var control = Control.none
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private static var volumeAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var defaultOutputAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private static func scalarAddr(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    init() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.attachToDefaultDevice() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddr, .main, block)
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        for (obj, addr, blk) in listeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(obj, &a, .main, blk)
        }
        listeners.removeAll()

        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddr, 0, nil, &size, &id)
        device = id
        deviceName = Self.name(of: id)
        control = Self.findControl(id)
        canSet = control != .none
        log.info("Volume output \(self.deviceName ?? "?", privacy: .public): \(String(describing: self.control), privacy: .public)")

        // Listen to everything that might move; registering an unsupported address just fails.
        let addrs = [Self.volumeAddr, Self.muteAddr] + [0, 1, 2].map { Self.scalarAddr($0) }
        for addr in addrs where AudioObjectHasProperty(id, [addr]) {
            var a = addr
            let blk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.read() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &a, .main, blk) == noErr { listeners.append((id, addr, blk)) }
        }
        read()
    }

    private static func findControl(_ id: AudioDeviceID) -> Control {
        guard id != kAudioObjectUnknown else { return .none }
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(id, &volumeAddr),
           AudioObjectIsPropertySettable(id, &volumeAddr, &settable) == noErr, settable.boolValue {
            return .main
        }
        let settableChannels = [UInt32(0), 1, 2].filter { element in
            var a = scalarAddr(element)
            var s: DarwinBoolean = false
            return AudioObjectHasProperty(id, &a) && AudioObjectIsPropertySettable(id, &a, &s) == noErr && s.boolValue
        }
        if settableChannels.contains(0) { return .channels([0]) }
        return settableChannels.isEmpty ? .none : .channels(settableChannels)
    }

    private static func name(of id: AudioDeviceID) -> String? {
        guard id != kAudioObjectUnknown else { return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private func read() {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        switch control {
        case .main:
            if AudioObjectGetPropertyData(device, &Self.volumeAddr, 0, nil, &size, &v) == noErr { volume = v }
        case .channels(let elements):
            // Report the loudest channel, like the system does when the balance is off-center.
            let values: [Float32] = elements.compactMap { element in
                var a = Self.scalarAddr(element)
                var c: Float32 = 0
                var s = UInt32(MemoryLayout<Float32>.size)
                return AudioObjectGetPropertyData(device, &a, 0, nil, &s, &c) == noErr ? c : nil
            }
            if let m = values.max() { volume = m }
        case .none:
            break
        }
        var m: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &Self.muteAddr, 0, nil, &size, &m) == noErr { isMuted = m != 0 }
    }

    func set(_ value: Float) {
        guard canSet else { return }
        var v = Float32(min(1, max(0, value)))
        let size = UInt32(MemoryLayout<Float32>.size)
        switch control {
        case .main: AudioObjectSetPropertyData(device, &Self.volumeAddr, 0, nil, size, &v)
        case .channels(let elements):
            for element in elements {
                var a = Self.scalarAddr(element)
                AudioObjectSetPropertyData(device, &a, 0, nil, size, &v)
            }
        case .none: return
        }
        if v > 0, isMuted { setMuted(false) }
        volume = v
    }

    func setMuted(_ muted: Bool) {
        var m: UInt32 = muted ? 1 : 0
        if AudioObjectSetPropertyData(device, &Self.muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m) == noErr {
            isMuted = muted
        }
    }

    /// Steps like the system: 1/16 per press, rounded to the grid.
    func step(by delta: Float) {
        let steps = 1 / abs(delta)
        let next = ((volume * steps).rounded() + (delta > 0 ? 1 : -1)) / steps
        set(next)
    }
}
