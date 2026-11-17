import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Wallpapers saved on disk: downloads plus the user's own imported images/videos.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var items: [LocalWallpaper] = []
    @Published private(set) var inFlight: Set<String> = []
    @Published private(set) var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])

    let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("library.json") }

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wallflow/Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([LocalWallpaper].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func item(id: String) -> LocalWallpaper? { items.first { $0.id == id } }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    /// Bytes used by the library folder.
    func diskUsage() -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    func download(_ wallpaper: Wallpaper) async throws -> LocalWallpaper {
        if let existing = item(id: wallpaper.id) { return existing }
        inFlight.insert(wallpaper.id)
        defer { inFlight.remove(wallpaper.id) }

        if let ping = wallpaper.downloadPing { // required by Unsplash API guidelines
            var req = URLRequest(url: ping)
            req.setValue("Client-ID \(Prefs.key("Unsplash"))", forHTTPHeaderField: "Authorization")
            _ = try? await HTTP.session.data(for: req)
        }

        let (tmp, response) = try await HTTP.session.download(from: wallpaper.fullURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProviderError.http(http.statusCode)
        }
        let dest = folder.appendingPathComponent(Self.safeName(wallpaper.id))
            .appendingPathExtension(wallpaper.fileExtension)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)

        let item = LocalWallpaper(id: wallpaper.id, kind: wallpaper.kind, path: dest.path,
                                  title: wallpaper.title, addedAt: Date())
        if item.kind == .live { try? await Poster.make(video: item.fileURL, to: item.posterURL) }
        add(item)
        return item
    }

    /// Copy the user's own images or videos into the library.
    func importFiles(_ urls: [URL]) async {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let type = UTType(filenameExtension: url.pathExtension) else { continue }
            let kind: WallpaperKind
            if type.conforms(to: .movie) || type.conforms(to: .video) { kind = .live }
            else if type.conforms(to: .image) { kind = .still }
            else { continue }

            let id = "local-\(UUID().uuidString)"
            let dest = folder.appendingPathComponent(id).appendingPathExtension(url.pathExtension.lowercased())
            do { try FileManager.default.copyItem(at: url, to: dest) } catch { continue }
            let item = LocalWallpaper(id: id, kind: kind, path: dest.path,
                                      title: url.deletingPathExtension().lastPathComponent, addedAt: Date())
            if kind == .live { try? await Poster.make(video: dest, to: item.posterURL) }
            add(item)
        }
    }

    func remove(_ item: LocalWallpaper) {
        try? FileManager.default.removeItem(at: item.fileURL)
        if item.kind == .live { try? FileManager.default.removeItem(at: item.posterURL) }
        items.removeAll { $0.id == item.id }
        if favorites.contains(item.id) { toggleFavorite(item.id) }
        save()
    }

    private func add(_ item: LocalWallpaper) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }

    private static func safeName(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" })
    }
}

enum Poster {
    struct Failed: Error {}

    /// Grab the first frame of a video as a JPEG — used for thumbnails and the static/lock-screen picture.
    static func make(video: URL, to output: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 6016, height: 6016)
        let (cgImage, _) = try await generator.image(at: .zero)
        guard let data = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { throw Failed() }
        try data.write(to: output, options: .atomic)
    }
}
