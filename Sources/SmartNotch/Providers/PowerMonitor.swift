import Foundation
import IOKit.ps

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
}

/// Watches the power source through IOKit's change notification (event-driven, no polling) and
/// reports the moment a charger is connected or disconnected, for the charging animations.
@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var battery: BatteryInfo?
    /// Called on a battery ↔ AC transition (true = plugged in). Not called at launch.
    var onPowerSourceChanged: ((BatteryInfo, _ pluggedIn: Bool) -> Void)?

    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        battery = Self.read()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            // Delivered on the main run loop (added below).
            MainActor.assumeIsolated { me.powerChanged() }
        }, ctx)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    private func powerChanged() {
        let old = battery
        let new = Self.read()
        battery = new
        if let new, let old, new.onAC != old.onAC { onPowerSourceChanged?(new, new.onAC) }
    }

    /// Internal battery only; nil on desktops.
    nonisolated static func read() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryInfo(percent: Int((Double(cur) / Double(max) * 100).rounded()),
                               isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                               onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }
}
