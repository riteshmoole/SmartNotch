import SwiftUI

/// A notch outline: concave "flares" where it meets the top edge, rounded bottom corners.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set { flare = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let f = flare, r = min(bottomRadius, (rect.width - 2 * f) / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.minY + f), control: CGPoint(x: rect.minX + f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f + r, y: rect.maxY), control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.maxY - r), control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var app: AppState
    @ObservedObject var settings: Settings
    @ObservedObject var themes: ThemeStore

    private var g: NotchGeometry { vm.geometry }
    private var theme: Theme { themes.current }
    private var expanded: Bool { vm.isExpanded }
    /// What the island is drawn with right now: glass themes only apply while open.
    private var drawTheme: Theme { expanded ? theme : theme.collapsed }

    private var islandSize: CGSize {
        if expanded { return NotchGeometry.expandedSize }
        let wing = app.activity.wingWidth
        return CGSize(width: g.coreSize.width + wing * 2 + g.flare * 2, height: g.coreSize.height)
    }

    private var shape: AnyShape {
        if g.hasNotch {
            return AnyShape(NotchShape(flare: expanded ? 14 : g.flare, bottomRadius: expanded ? 28 : 10))
        }
        return AnyShape(RoundedRectangle(cornerRadius: expanded ? 26 : g.coreSize.height / 2, style: .continuous))
    }

    private var animation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.12)
            : .spring(response: 0.38, dampingFraction: 0.82)
    }

    private var glowColor: Color {
        if !expanded && app.activity == .charging {
            return app.chargingFlash?.pluggedIn == false ? .clear : ChargingBattery.green.opacity(0.55)
        }
        guard expanded else { return .clear }
        if settings.glowEnabled && theme.glow { return theme.glowSwiftColor.opacity(0.75) }
        return .black.opacity(theme.isGlass ? 0.25 : 0.5)
    }

    var body: some View {
        let panel = g.panelFrame.size
        ZStack(alignment: .top) {
            // Margin clicks (only reachable while expanded) close the island.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { AppActions.collapse() }

            ZStack(alignment: .top) {
                if expanded && theme.isGlass {
                    GlassBackground(shape: shape, theme: theme, frost: settings.glassFrost)
                } else {
                    shape.fill(drawTheme.backgroundColor)
                }
                if expanded {
                    ExpandedView(app: app, geometry: g, theme: theme)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedWingsView(app: app, nowPlaying: app.nowPlaying, timers: app.timers, call: app.call,
                                       geometry: g, theme: drawTheme)
                        .transition(.opacity)
                }
                if vm.isDropTargeted {
                    shape.stroke(theme.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            .frame(width: islandSize.width, height: islandSize.height)
            .clipShape(shape)
            .shadow(color: glowColor, radius: expanded ? max(10, theme.glowRadius) : (app.activity == .charging ? 10 : 0))
            .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
                guard settings.shelfEnabled else { return false }
                app.shelf.add(providers: providers)
                app.activeTab = .shelf
                return true
            }
            .padding(.top, g.topInset)
            .environment(\.colorScheme, drawTheme.colorScheme)
            .environment(\.notchTheme, drawTheme)
            .foregroundStyle(drawTheme.foregroundColor)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("SmartNotch")
        }
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .animation(animation, value: expanded)
        .animation(animation, value: app.activity)
    }
}

/// Liquid Glass behind the open island: the system material on macOS 26+, a blur on older systems.
private struct GlassBackground: View {
    let shape: AnyShape
    let theme: Theme
    /// 0 = clearest, 1 = most frosted (Settings → Appearance → Glass clarity).
    let frost: Double

    /// Below this the slider uses Apple's `.clear` glass (see-through with refraction), above it `.regular`.
    private static let clearRange = 0.35

    // 0 → untinted clear glass; up to 0.2 wash at the top of the clear range; then regular glass
    // with a wash up to 0.7 (light needs more than dark to keep black text readable).
    private var tintOpacity: Double {
        if frost < Self.clearRange { return frost / Self.clearRange * 0.2 }
        return (frost - Self.clearRange) / (1 - Self.clearRange) * (theme.isLight ? 0.7 : 0.65)
    }
    private var tint: Color { theme.backgroundColor.opacity(tintOpacity) }

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect((frost < Self.clearRange ? Glass.clear : Glass.regular).tint(tint), in: shape)
        } else {
            ZStack {
                VisualEffectBlur(material: theme.isLight ? .popover : .hudWindow)
                    .opacity(min(1, 0.3 + frost * 1.2))
                tint
            }
            .clipShape(shape)
        }
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
