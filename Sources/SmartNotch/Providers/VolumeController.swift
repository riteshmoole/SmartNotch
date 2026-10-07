import AudioToolbox
import CoreAudio
import Foundation

/// Reads and sets the default output device's volume through CoreAudio. `canSet` is false for
/// outputs with no software volume (e.g. many HDMI/DisplayPort displays). Callers must then leave
/// hardware keys alone.
@MainActor
final class VolumeController: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var canSet = false

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private static var volumeAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var defaultOutputAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

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

        var settable: DarwinBoolean = false
        canSet = AudioObjectHasProperty(id, &Self.volumeAddr)
            && AudioObjectIsPropertySettable(id, &Self.volumeAddr, &settable) == noErr && settable.boolValue

        for addr in [Self.volumeAddr, Self.muteAddr] where AudioObjectHasProperty(id, [addr]) {
            var a = addr
            let blk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.read() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &a, .main, blk) == noErr { listeners.append((id, addr, blk)) }
        }
        read()
    }

    private func read() {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &Self.volumeAddr, 0, nil, &size, &v) == noErr { volume = v }
        var m: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &Self.muteAddr, 0, nil, &size, &m) == noErr { isMuted = m != 0 }
    }

    func set(_ value: Float) {
        guard canSet else { return }
        var v = Float32(min(1, max(0, value)))
        AudioObjectSetPropertyData(device, &Self.volumeAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
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
