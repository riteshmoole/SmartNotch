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
        return .black.opacity(0.5)
    }

    var body: some View {
        let panel = g.panelFrame.size
        ZStack(alignment: .top) {
            // Margin clicks (only reachable while expanded) close the island.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { AppActions.collapse() }

            ZStack(alignment: .top) {
                shape.fill(theme.backgroundColor)
                if expanded {
                    ExpandedView(app: app, geometry: g, theme: theme)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedWingsView(app: app, nowPlaying: app.nowPlaying, timers: app.timers, call: app.call,
                                       geometry: g, theme: theme)
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
            .environment(\.colorScheme, .dark)
            .foregroundStyle(theme.foregroundColor)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("SmartNotch")
        }
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .animation(animation, value: expanded)
        .animation(animation, value: app.activity)
    }
}
