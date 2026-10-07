import AppKit
import Combine

enum NotchTab: String, CaseIterable, Identifiable {
    case media, shelf, clipboard, utilities, mirror
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .media: "music.note"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .utilities: "square.grid.2x2"
        case .mirror: "camera"
        }
    }
    var title: String {
        switch self {
        case .media: "Now Playing"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .utilities: "Utilities"
        case .mirror: "Mirror"
        }
    }
}

struct PowerFlash: Equatable {
    let battery: BatteryInfo
    let pluggedIn: Bool
    /// How long the live activity stays up. Unplug is a quieter, shorter beat.
    var duration: TimeInterval { pluggedIn ? 2.5 : 1.8 }
}

enum HUDKind: Equatable {
    case volume(level: Float, muted: Bool)
}

/// What the collapsed island shows beside the notch, highest priority first.
enum CollapsedActivity: Equatable {
    case none, hud, charging, call, timer, media

    var wingWidth: CGFloat {
        switch self {
        case .none: 0
        case .media: 36
        case .timer: 56
        case .call: 64
        case .hud: 76
        case .charging: 92
        }
    }
}

/// Root state shared by every notch window. Owns all providers and decides which of them
/// should be doing work, so nothing polls while the notch is collapsed.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings = Settings.shared
    let nowPlaying = NowPlayingProvider()
    let shelf = ShelfStore()
    let clipboard = ClipboardMonitor()
    let stats = SystemStats()
    let keepAwake = KeepAwake()
    let camera = CameraPreview()
    let timers = TimerStore()
    let call = CallActivityMonitor()
    let volume = VolumeController()
    let mediaKeys = MediaKeyTap()
    let themes = ThemeStore()
    let updates = UpdateChecker()
    let power = PowerMonitor()

    @Published var activeTab: NotchTab = .media { didSet { visibilityChanged() } }
    @Published private(set) var isExpanded = false
    @Published private(set) var hud: HUDKind?
    /// Set briefly after a charger is connected or disconnected (iPhone-style charging animation).
    @Published private(set) var chargingFlash: PowerFlash?
    @Published private(set) var activity: CollapsedActivity = .none

    private var hudHide: DispatchWorkItem?
    private var chargingHide: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    func start() {
        let s = settings
        s.$mediaEnabled.removeDuplicates().sink { [weak self] on in
            on ? self?.nowPlaying.start() : self?.nowPlaying.stop()
        }.store(in: &bag)
        s.$clipboardEnabled.removeDuplicates().sink { [weak self] on in
            on ? self?.clipboard.start() : self?.clipboard.stop()
        }.store(in: &bag)
        s.$callActivityEnabled.removeDuplicates().sink { [weak self] on in
            on ? self?.call.start() : self?.call.stop()
        }.store(in: &bag)
        s.$hudReplacement.removeDuplicates().sink { [weak self] on in
            self?.mediaKeys.setEnabled(on)
        }.store(in: &bag)
        s.$checkForUpdates.removeDuplicates().sink { [weak self] on in
            on ? self?.updates.start() : self?.updates.stop()
        }.store(in: &bag)

        call.isOwnCameraActive = { [weak self] in self?.camera.isRunning ?? false }
        mediaKeys.volume = volume
        mediaKeys.onHUD = { [weak self] kind in self?.showHUD(kind) }
        shelf.startAutoClear()
        power.onPowerSourceChanged = { [weak self] info, pluggedIn in
            log.info("Charger \(pluggedIn ? "connected" : "disconnected", privacy: .public) (\(info.percent, privacy: .public)%)")
            guard let self, self.settings.chargingAnimation else { return }
            self.showCharging(PowerFlash(battery: info, pluggedIn: pluggedIn))
        }
        power.start()

        // Recompute the collapsed activity whenever an input changes. Hop async so the new value is set.
        let triggers: [AnyPublisher<Void, Never>] = [
            nowPlaying.$track.map { _ in () }.eraseToAnyPublisher(),
            timers.$timers.map { _ in () }.eraseToAnyPublisher(),
            timers.$finished.map { _ in () }.eraseToAnyPublisher(),
            call.$isInCall.map { _ in () }.eraseToAnyPublisher(),
            $hud.map { _ in () }.eraseToAnyPublisher(),
            $chargingFlash.map { _ in () }.eraseToAnyPublisher(),
            s.$showWings.map { _ in () }.eraseToAnyPublisher(),
            s.$mediaEnabled.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.recomputeActivity() }
            .store(in: &bag)
    }

    func stop() {
        nowPlaying.stop()
        clipboard.stop()
        call.stop()
        camera.setActive(false)
        keepAwake.set(false)
        mediaKeys.setEnabled(false)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded, activeTab == .mirror { activeTab = .media } // never turn the camera on just by opening
        isExpanded = expanded
        visibilityChanged()
    }

    private func visibilityChanged() {
        stats.setActive(isExpanded && activeTab == .utilities)
        camera.setActive(isExpanded && activeTab == .mirror)
    }

    func showHUD(_ kind: HUDKind) {
        hud = kind
        hudHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func showCharging(_ flash: PowerFlash) {
        chargingFlash = flash
        chargingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.chargingFlash = nil }
        chargingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + flash.duration, execute: work)
    }

    func recomputeActivity() {
        let next: CollapsedActivity
        if hud != nil { next = .hud }
        else if chargingFlash != nil { next = .charging }
        else if !settings.showWings { next = .none }
        else if call.isInCall { next = .call }
        else if !timers.timers.isEmpty || timers.finished != nil { next = .timer }
        else if settings.mediaEnabled, nowPlaying.track?.isPlaying == true { next = .media }
        else { next = .none }
        if next != activity { activity = next }
    }
}
