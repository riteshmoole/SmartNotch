import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var settings: Settings
    let theme: Theme

    var body: some View {
        if !settings.shelfEnabled {
            EmptyStateView(symbol: "tray", title: "Shelf is off", detail: "Turn it on in Settings → Modules.")
        } else if shelf.items.isEmpty {
            dropHint
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold)).opacity(0.6)
                    Spacer()
                    if shelf.isAirDropAvailable {
                        Button { shelf.airDrop(shelf.items) } label: { Label("AirDrop All", systemImage: "airplayaudio") }
                            .buttonStyle(PillButtonStyle())
                    }
                    Button { shelf.clear() } label: { Label("Clear", systemImage: "trash") }
                        .buttonStyle(PillButtonStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf, theme: theme)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("Drag items out to any app or folder. Shelf clears after \(settings.shelfAutoClearHours) h.")
                    .font(.system(size: 9)).opacity(0.45)
            }
        }
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .opacity(0.35)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).opacity(0.7)
                    Text("Drop files here").font(.system(size: 13, weight: .semibold))
                    Text("Drag any file onto the notch to park it. Drag it out, or AirDrop it.")
                        .font(.system(size: 11)).opacity(0.6)
                }
            }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let shelf: ShelfStore
    let theme: Theme
    @ViewState private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 52, height: 52)
                .overlay(alignment: .bottomLeading) {
                    if item.isReference {
                        Image(systemName: "link").font(.system(size: 9, weight: .bold))
                            .padding(3).background(.black.opacity(0.7), in: Circle())
                    }
                }
            Text(verbatim: item.name.displaySafe)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.1 : 0)))
        // Drag, double-click and right-click are handled natively (see FileDragSource).
        .overlay(FileDragSource(item: item, shelf: shelf))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: 0)
                .accessibilityLabel("Remove from shelf")
            }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name.displaySafe)
    }
}
