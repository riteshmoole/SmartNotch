import AppKit

struct CountdownTimer: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let duration: TimeInterval
    let endDate: Date
}

/// In-app countdown timers. A one-shot Timer fires at each end date, so nothing ticks in the
/// background. The countdown text comes from SwiftUI's TimelineView, which only runs while visible.
@MainActor
final class TimerStore: ObservableObject {
    @Published private(set) var timers: [CountdownTimer] = []
    /// The timer that just finished (shown for a few seconds).
    @Published private(set) var finished: CountdownTimer?

    private var fireTimers: [UUID: Timer] = [:]

    var soonest: CountdownTimer? { timers.min { $0.endDate < $1.endDate } }

    func start(minutes: Double, label: String? = nil) {
        let d = minutes * 60
        let t = CountdownTimer(label: label ?? Self.label(for: d), duration: d, endDate: Date().addingTimeInterval(d))
        timers.append(t)
        let fire = Timer(fire: t.endDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.complete(t) }
        }
        fire.tolerance = 0.2
        RunLoop.main.add(fire, forMode: .common)
        fireTimers[t.id] = fire
    }

    func cancel(_ t: CountdownTimer) {
        fireTimers.removeValue(forKey: t.id)?.invalidate()
        timers.removeAll { $0.id == t.id }
    }

    private func complete(_ t: CountdownTimer) {
        fireTimers.removeValue(forKey: t.id)
        timers.removeAll { $0.id == t.id }
        finished = t
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.finished == t { self?.finished = nil }
        }
    }

    private static func label(for seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60 > 0 ? "\(m % 60) min" : "")" : "\(m) min"
    }
}
