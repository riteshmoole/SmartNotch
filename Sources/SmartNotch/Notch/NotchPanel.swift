import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space,
/// including beside full-screen apps. It ignores the mouse while collapsed, so clicks
/// fall through to the menu bar.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Esc closes the island while it holds keyboard focus (glass themes).
    override func cancelOperation(_ sender: Any?) { AppActions.collapse() }
    // Borderless windows would otherwise be pushed below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchViewModel: ObservableObject {
    let geometry: NotchGeometry
    @Published var isExpanded = false
    @Published var isDropTargeted = false
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

/// One panel per screen.
@MainActor
final class NotchWindowController {
    let geometry: NotchGeometry
    let vm: NotchViewModel
    let panel: NotchPanel

    init(geometry: NotchGeometry, state: AppState) {
        self.geometry = geometry
        vm = NotchViewModel(geometry: geometry)
        panel = NotchPanel(frame: geometry.panelFrame)
        let host = NSHostingView(rootView: NotchRootView(vm: vm, app: state, settings: state.settings, themes: state.themes))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: geometry.panelFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.sharingType = state.settings.hideFromScreenShare ? .none : .readOnly
        panel.setFrame(geometry.panelFrame, display: false)
        panel.orderFrontRegardless()
    }

    var expandedRect: CGRect { geometry.expandedRect }

    func setExpanded(_ expanded: Bool, takeFocus: Bool = false) {
        vm.isExpanded = expanded
        panel.ignoresMouseEvents = !expanded
        if !expanded { vm.isDropTargeted = false }
        // macOS draws Liquid Glass in its clear, refracting form only in the key window; anywhere
        // else it falls back to a flat frost. So glass themes take focus while open. The panel is
        // non-activating, so the frontmost app stays active, and re-ordering the panel on close
        // hands keyboard focus straight back to it.
        if expanded && takeFocus {
            panel.makeKey()
        } else if !expanded && panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
