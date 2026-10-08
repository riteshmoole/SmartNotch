import SwiftUI

struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var settings: Settings
    let theme: Theme
    @ViewState private var copiedID: UUID?

    var body: some View {
        if !settings.clipboardEnabled {
            EmptyStateView(symbol: "doc.on.clipboard", title: "Clipboard history is off", detail: "Turn it on in Settings → Modules.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(settings.clipboardPersist ? "Saved on this Mac" : "Memory only. Gone when you quit.",
                          systemImage: settings.clipboardPersist ? "internaldrive" : "lock.fill")
                        .font(.system(size: 10, weight: .medium)).opacity(0.55)
                    Spacer()
                    Button { clipboard.isPaused.toggle() } label: {
                        Label(clipboard.isPaused ? "Resume" : "Pause", systemImage: clipboard.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: theme.accentColor, active: clipboard.isPaused))
                    Button { clipboard.clear() } label: { Label("Clear", systemImage: "trash") }
                        .buttonStyle(PillButtonStyle())
                }
                if clipboard.items.isEmpty {
                    EmptyStateView(symbol: "doc.on.clipboard", title: "Nothing copied yet",
                                   detail: "Copied text and images show up here. Passwords are skipped.")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(clipboard.items) { item in row(item) }
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        Button {
            clipboard.copy(item)
            copiedID = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if copiedID == item.id { copiedID = nil } }
        } label: {
            HStack(spacing: 8) {
                if let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "doc.on.doc").frame(width: 16, height: 16).opacity(0.5)
                }
                switch item.content {
                case .text(let s):
                    Text(verbatim: String(s.displaySafe.trimmingCharacters(in: .whitespaces).prefix(300)))
                        .font(.system(size: 11)).lineLimit(1)
                case .image(let img):
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Image").font(.system(size: 11)).opacity(0.6)
                }
                Spacer(minLength: 4)
                Text(copiedID == item.id ? "Copied" : item.date.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 9)).opacity(0.5)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.foregroundColor.opacity(copiedID == item.id ? 0.18 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button("Delete") { clipboard.remove(item) }
        }
        .accessibilityLabel(item.text.map { "Copy \($0.prefix(60))" } ?? "Copy image")
    }
}
