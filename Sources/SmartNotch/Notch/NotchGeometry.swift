import AppKit

/// Where the island lives on one screen. On a notched screen the collapsed core is exactly the
/// hardware cutout; elsewhere it is a synthesized floating pill. All rects are global screen coords.
struct NotchGeometry {
    static let expandedSize = CGSize(width: 600, height: 236)
    static let panelMargin: CGFloat = 36 // room for glow/shadow around the expanded island

    let screen: NSScreen
    let hasNotch: Bool
    /// Collapsed core size (notch cutout, or pill).
    let coreSize: CGSize
    /// Gap between the top of the screen and the island (0 for a real notch).
    let topInset: CGFloat

    var screenFrame: CGRect { screen.frame }
    var centerX: CGFloat { screenFrame.midX }
    var isPill: Bool { !hasNotch }
    /// Concave "flare" where a notch shape meets the top edge.
    var flare: CGFloat { hasNotch ? 6 : 0 }

    static func make(for screen: NSScreen, forcePill: Bool) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if !forcePill, top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let width = r.minX - l.maxX
            if width > 0 {
                return NotchGeometry(screen: screen, hasNotch: true, coreSize: CGSize(width: width, height: top), topInset: 0)
            }
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let barHeight = menuBar >= 20 && menuBar <= 44 ? menuBar : 24
        let pillHeight: CGFloat = min(26, barHeight - 4)
        return NotchGeometry(screen: screen, hasNotch: false,
                             coreSize: CGSize(width: 170, height: pillHeight),
                             topInset: max(2, (barHeight - pillHeight) / 2))
    }

    /// Fixed panel frame: large enough for the expanded island plus glow.
    var panelFrame: CGRect {
        let w = Self.expandedSize.width + Self.panelMargin * 2
        let h = Self.expandedSize.height + topInset + Self.panelMargin
        return CGRect(x: centerX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
    }

    var expandedRect: CGRect {
        let s = Self.expandedSize
        return CGRect(x: centerX - s.width / 2, y: screenFrame.maxY - topInset - s.height, width: s.width, height: s.height)
    }

    /// Hit area of the collapsed island. Extends up to the screen edge so the very top pixel row counts.
    func collapsedRect(wing: CGFloat) -> CGRect {
        let w = coreSize.width + wing * 2 + flare * 2
        return CGRect(x: centerX - w / 2, y: screenFrame.maxY - topInset - coreSize.height - 2,
                      width: w, height: coreSize.height + topInset + 4)
    }

    /// Area where a file drag "pulls" the shelf open.
    var dragZone: CGRect { collapsedRect(wing: 0).insetBy(dx: -90, dy: -50) }
}
