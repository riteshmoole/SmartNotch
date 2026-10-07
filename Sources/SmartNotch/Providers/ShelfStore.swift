import AppKit
import UniformTypeIdentifiers

struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    /// Where the shelf's copy lives (or the original, for references).
    let url: URL
    let originalPath: String
    let name: String
    let addedAt: Date
    /// True when the file sits on another volume, so we kept a reference instead of a clone.
    let isReference: Bool
}

/// Temporary file shelf. Dropped files are *cloned* into Application Support.
/// On APFS that is copy-on-write (clonefile), so it uses no extra disk until either copy changes,
/// and the shelf survives the original being moved or deleted. Files on another volume are
/// referenced instead of copied, so a 50 GB drag from an external drive never fills the disk.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let dir = AppPaths.dir("Shelf")
    private var indexURL: URL { dir.appendingPathComponent("items.json") }
    private var clearTimer: Timer?

    init() {
        load()
        purgeExpired()
    }

    // MARK: Adding

    func add(providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let url else { return }
                DispatchQueue.main.async { self?.add(urls: [url]) }
            }
        }
    }

    func add(urls: [URL]) {
        let existing = Set(items.map(\.originalPath))
        let dir = self.dir
        for src in urls where src.isFileURL && !existing.contains(src.path) {
            Task.detached(priority: .userInitiated) {
                guard let item = Self.ingest(src, into: dir) else { return }
                await MainActor.run { [weak self] in
                    guard let self, !self.items.contains(where: { $0.originalPath == item.originalPath }) else { return }
                    self.items.insert(item, at: 0)
                    self.save()
                }
            }
        }
    }

    private nonisolated static func ingest(_ src: URL, into dir: URL) -> ShelfItem? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return nil }
        let id = UUID()
        let name = src.lastPathComponent
        let sameVolume: Bool = {
            let a = try? src.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            let b = try? dir.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            return a != nil && a == b
        }()
        if sameVolume {
            let folder = dir.appendingPathComponent(id.uuidString, isDirectory: true)
            let dest = folder.appendingPathComponent(name)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dest) // APFS: clonefile
                return ShelfItem(id: id, url: dest, originalPath: src.path, name: name, addedAt: Date(), isReference: false)
            } catch {
                try? fm.removeItem(at: folder)
            }
        }
        return ShelfItem(id: id, url: src, originalPath: src.path, name: name, addedAt: Date(), isReference: true)
    }

    // MARK: Removing

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        deleteStorage(for: item)
        save()
    }

    func clear() {
        items.forEach(deleteStorage)
        items.removeAll()
        save()
    }

    private func deleteStorage(for item: ShelfItem) {
        guard !item.isReference else { return } // never touch the user's original
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.id.uuidString, isDirectory: true))
    }

    func startAutoClear() {
        clearTimer?.invalidate()
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        clearTimer = t
    }

    func purgeExpired() {
        let hours = Settings.shared.shelfAutoClearHours
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let expired = items.filter { $0.addedAt < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach(deleteStorage)
        items.removeAll { $0.addedAt < cutoff }
        save()
    }

    // MARK: Sharing

    func airDrop(_ items: [ShelfItem]) {
        let urls = items.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        AppActions.collapse()
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    var isAirDropAvailable: Bool { NSSharingService(named: .sendViaAirDrop) != nil }

    func reveal(_ item: ShelfItem) {
        AppActions.collapse()
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        AppActions.collapse()
        NSWorkspace.shared.open(item.url)
    }

    /// Sample data for `--snapshot --demo` marketing renders (not saved).
    func setDemo(_ items: [ShelfItem]) { self.items = items }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }
}
