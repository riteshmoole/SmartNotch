import CoreWLAN
import Foundation
import IOKit.ps

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
}

struct WiFiInfo: Equatable {
    var isOn: Bool
    var rssi: Int // 0 = not associated
    var bars: Int {
        guard rssi != 0 else { return 0 }
        return rssi > -55 ? 3 : rssi > -70 ? 2 : 1
    }
}

/// CPU / RAM / battery / Wi-Fi. Samples every 2 s only while the Utilities tab is visible.
/// SSID is deliberately not read, because it requires Location permission on current macOS.
@MainActor
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double?
    @Published private(set) var memUsed: Double?  // bytes
    @Published private(set) var battery: BatteryInfo?
    @Published private(set) var wifi: WiFiInfo?
    let memTotal = Double(ProcessInfo.processInfo.physicalMemory)

    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?

    func setActive(_ on: Bool) {
        if on, timer == nil {
            sample()
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !on {
            timer?.invalidate()
            timer = nil
            lastTicks = nil
        }
    }

    func sample() {
        sampleCPU()
        sampleMemory()
        refreshBattery()
        if let iface = CWWiFiClient.shared().interface() {
            wifi = WiFiInfo(isOn: iface.powerOn(), rssi: iface.rssiValue())
        } else {
            wifi = nil
        }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + sys + nice, total = busy + idle
        if let last = lastTicks, total > last.total {
            cpu = Double(busy - last.busy) / Double(total - last.total)
        }
        lastTicks = (busy, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let page = Double(getpagesize())
        // Roughly Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        memUsed = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { battery = nil; return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            battery = BatteryInfo(percent: Int((Double(cur) / Double(max) * 100).rounded()),
                                  isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                  onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
            return
        }
        battery = nil
    }

    /// Sample data for `--snapshot --demo` marketing renders.
    func setDemo(cpu: Double, memUsed: Double, battery: BatteryInfo, wifi: WiFiInfo) {
        self.cpu = cpu; self.memUsed = memUsed; self.battery = battery; self.wifi = wifi
    }
}
