import AppKit
import SwiftUI

/// Native AppKit drag for shelf items.
///
/// SwiftUI's `.onDrag { NSItemProvider(contentsOf:) }` turns into a *file promise*: the receiver
/// gets a temp copy in SwiftUI's cache with a generic name ("PNG image.png"). Messages can't take
/// that. A drag whose pasteboard item is the file's NSURL, as Finder does it, gives the receiver
/// the real file, and the system grants sandboxed apps access to it.
/// This view also handles double-click (open) and the right-click menu, because it sits on top of the tile.
struct FileDragSource: NSViewRepresentable {
    let item: ShelfItem
    let shelf: ShelfStore

    func makeNSView(context: Context) -> DragView {
        let v = DragView()
        v.update(item: item, shelf: shelf)
        return v
    }

    func updateNSView(_ v: DragView, context: Context) { v.update(item: item, shelf: shelf) }

    final class DragView: NSView {
        private var item: ShelfItem?
        private weak var shelf: ShelfStore?
        private var downEvent: NSEvent?

        func update(item: ShelfItem, shelf: ShelfStore) {
            self.item = item
            self.shelf = shelf
            toolTip = item.originalPath.displaySafe
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            downEvent = event
            if event.clickCount == 2, let item { MainActor.assumeIsolated { shelf?.open(item) } }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = downEvent, let item, FileManager.default.fileExists(atPath: item.url.path) else { return }
            let a = down.locationInWindow, b = event.locationInWindow
            guard hypot(b.x - a.x, b.y - a.y) > 3 else { return }
            downEvent = nil

            let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            let size = NSSize(width: 52, height: 52)
            let p = convert(down.locationInWindow, from: nil)
            dragItem.setDraggingFrame(NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                                      contents: icon)
            beginDraggingSession(with: [dragItem], event: down, source: ShelfDragCoordinator.shared)
        }

        override func mouseUp(with event: NSEvent) { downEvent = nil }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let item else { return nil }
            let menu = NSMenu()
            func add(_ title: String, _ action: @escaping () -> Void) {
                let mi = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
                let target = MenuAction(action)
                mi.target = target
                mi.representedObject = target // keep it alive with the menu
                menu.addItem(mi)
            }
            let shelf = self.shelf
            add("Open") { MainActor.assumeIsolated { shelf?.open(item) } }
            add("Show in Finder") { MainActor.assumeIsolated { shelf?.reveal(item) } }
            if MainActor.assumeIsolated({ shelf?.isAirDropAvailable ?? false }) {
                add("AirDrop") { MainActor.assumeIsolated { shelf?.airDrop([item]) } }
            }
            menu.addItem(.separator())
            add("Remove from Shelf") { MainActor.assumeIsolated { shelf?.remove(item) } }
            return menu
        }
    }
}

private final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// Long-lived dragging source, so a drag keeps working after the island collapses and the
/// tile view that started it is gone.
final class ShelfDragCoordinator: NSObject, NSDraggingSource {
    static let shared = ShelfDragCoordinator()

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : []
    }

    /// Get the island out of the way once the drag leaves it, so drop targets under it are reachable.
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { AppActions.collapseIfOutside(screenPoint) }
        }
    }
}
