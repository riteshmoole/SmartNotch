import SwiftUI

/// First-run screen. Explains how to open the notch and which optional features need which
/// permission. It asks for nothing. Every prompt waits until you use the feature that needs it.
struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Welcome to SmartNotch").font(.title2.bold())
                    Text("Your notch, but useful.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                row("cursorarrow.motionlines", "Hover or click the notch to open it.")
                row("keyboard", "Or press ⌃⌥Space from anywhere.")
                row("tray.and.arrow.down", "Drag files onto the notch to park them on the shelf.")
                row("menubar.rectangle", "Settings live in the menu bar icon.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions: only when you need them").font(.headline)
                Text("SmartNotch doesn't ask for anything now. macOS will ask the first time you use:")
                    .font(.callout).foregroundStyle(.secondary)
                perm("camera", "Mirror tab", "Camera")
                perm("speaker.wave.2", "Volume HUD (beta, off by default)", "Accessibility")
                perm("music.note", "Music/Spotify fallback (only if full media detection breaks)", "Automation")
                Text("Never requested: location, Full Disk Access, screen recording. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Get Started", action: onDone).keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 520, height: 520)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(Color.accentColor)
            Text(text)
        }
    }

    private func perm(_ symbol: String, _ feature: String, _ permission: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            Text(feature)
            Spacer()
            Text(permission).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
        }
        .font(.callout)
    }
}
