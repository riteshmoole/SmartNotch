import AppKit
import Combine

/// Owns the per-screen panels and turns mouse activity into expand/collapse decisions.
/// Mouse tracking is event-driven through NSEvent monitors; nothing polls.
/// Global mouse monitors need no permission. Only key monitors do.
@MainActor
final class NotchManager {
    private let state: AppState
    private var controllers: [NotchWindowController] = []
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()

    private var expanded: NotchWindowController?
    private var openWork: DispatchWorkItem?
    private var pendingOpenTarget: NotchWindowController?
    private var closeWork: DispatchWorkItem?
    /// Collapse-on-leave only applies once the pointer has actually been inside the open island
    /// (so the hotkey can open it while the mouse is elsewhere).
    private var pointerHasEntered = false
    private var dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount

    init(state: AppState) {
        self.state = state
        rebuild()
        installMonitors()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildSoon() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildSoon() }
        }
        let s = state.settings
        Publishers.Merge3(s.$forcePill.map { _ in () }, s.$showPillOnNotchless.map { _ in () }, s.$hideFromScreenShare.map { _ in () })
            .dropFirst(3)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.rebuild() }
            .store(in: &bag)
    }

    // MARK: Screens

    private var rebuildWork: DispatchWorkItem?
    private func rebuildSoon() {
        rebuildWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.rebuild() }
        rebuildWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func rebuild() {
        collapse()
        controllers.forEach { $0.close() }
        let s = state.settings
        controllers = NSScreen.screens.compactMap { screen in
            let g = NotchGeometry.make(for: screen, forcePill: s.forcePill)
            if g.isPill && !s.showPillOnNotchless && !s.forcePill { return nil }
            return NotchWindowController(geometry: g, state: state)
        }
        log.info("Notch panels: \(self.controllers.count, privacy: .public)")
    }

    // MARK: Public actions

    func toggle() {
        if expanded != nil { collapse(); return }
        let p = NSEvent.mouseLocation
        let target = controllers.first { $0.geometry.screenFrame.contains(p) } ?? controllers.first
        if let target { expand(target) }
    }

    func expand(_ c: NotchWindowController, tab: NotchTab? = nil) {
        cancelOpen(); cancelClose()
        if let e = expanded, e !== c { e.setExpanded(false) }
        if let tab { state.activeTab = tab }
        expanded = c
        pointerHasEntered = c.expandedRect.contains(NSEvent.mouseLocation)
        c.setExpanded(true)
        state.setExpanded(true)
    }

    func collapse() {
        cancelOpen(); cancelClose()
        guard let e = expanded else { return }
        e.setExpanded(false)
        expanded = nil
        state.setExpanded(false)
    }

    func collapseIfOutside(_ p: CGPoint) {
        guard let e = expanded, !e.expandedRect.insetBy(dx: -8, dy: -8).contains(p) else { return }
        collapse()
    }

    // MARK: Mouse

    private func installMonitors() {
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: types, handler: { [weak self] e in
            let type = e.type
            MainActor.assumeIsolated { self?.handle(type, global: true) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] e in
            let type = e.type
            MainActor.assumeIsolated { self?.handle(type, global: false) }
            return e
        }) { monitors.append(l) }
    }

    private func handle(_ type: NSEvent.EventType, global: Bool) {
        let p = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown, .rightMouseDown:
            dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            if let e = expanded {
                // Global clicks never land on our own panel, so any of them is "outside".
                if global || !e.expandedRect.contains(p) { collapse() }
            } else if type == .leftMouseDown, let c = collapsedController(at: p) {
                expand(c)
            }

        case .mouseMoved, .leftMouseDragged:
            if type == .leftMouseDragged { checkFileDrag(at: p) }
            if let e = expanded {
                if e.expandedRect.insetBy(dx: -8, dy: -8).contains(p) {
                    pointerHasEntered = true
                    cancelClose()
                } else if pointerHasEntered && !e.vm.isDropTargeted {
                    scheduleClose()
                }
            } else if type == .mouseMoved, state.settings.hoverToOpen, let c = collapsedController(at: p) {
                scheduleOpen(c)
            } else {
                cancelOpen()
            }

        default: break
        }
    }

    private func collapsedController(at p: CGPoint) -> NotchWindowController? {
        let wing = state.activity.wingWidth
        return controllers.first { $0.geometry.collapsedRect(wing: wing).contains(p) }
    }

    /// Opens the shelf only for a *new* drag that carries file URLs and comes near the notch.
    /// Window drags, text selections and stale drag pasteboards are ignored.
    private func checkFileDrag(at p: CGPoint) {
        guard state.settings.shelfEnabled else { return }
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != dragCountAtMouseDown,
              let c = controllers.first(where: { $0.geometry.dragZone.contains(p) }),
              expanded !== c,
              pb.types?.contains(.fileURL) == true else { return }
        expand(c, tab: .shelf)
        pointerHasEntered = true
    }

    private func scheduleOpen(_ c: NotchWindowController) {
        if openWork != nil, pendingOpenTarget === c { return }
        cancelOpen()
        pendingOpenTarget = c
        let work = DispatchWorkItem { [weak self, weak c] in
            guard let self, let c else { return }
            self.openWork = nil
            self.pendingOpenTarget = nil
            if self.collapsedController(at: NSEvent.mouseLocation) === c { self.expand(c) }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, state.settings.hoverDelay), execute: work)
    }

    private func cancelOpen() {
        openWork?.cancel(); openWork = nil; pendingOpenTarget = nil
    }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.closeWork = nil
            self?.collapse()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func cancelClose() {
        closeWork?.cancel(); closeWork = nil
    }
}
