import Foundation

enum WallpaperKind: String, Codable, CaseIterable, Identifiable {
    case still, live
    var id: String { rawValue }
    var title: String { self == .still ? "Wallpapers" : "Live Wallpapers" }
}

/// A wallpaper found online (not yet downloaded).
struct Wallpaper: Identifiable, Hashable {
    let id: String              // globally unique, e.g. "pexels-v-12345"
    let source: String          // provider name
    let kind: WallpaperKind
    let thumbnailURL: URL       // small image for the grid
    let previewURL: URL         // medium image / small video for the detail view
    let fullURL: URL            // highest quality file
    let width: Int
    let height: Int
    let author: String?
    let pageURL: URL?
    var downloadPing: URL? = nil // Unsplash requires a ping when a photo is downloaded

    var resolutionLabel: String { "\(width)×\(height)" }
    var title: String { author.map { "\(source) · \($0)" } ?? source }
    var fileExtension: String {
        let ext = fullURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "webp", "mp4", "mov", "m4v"].contains(ext) { return ext }
        return kind == .live ? "mp4" : "jpg"
    }
}

/// A wallpaper stored on disk in the user's library.
struct LocalWallpaper: Identifiable, Codable, Hashable {
    let id: String
    let kind: WallpaperKind
    let path: String
    let title: String
    let addedAt: Date

    var fileURL: URL { URL(fileURLWithPath: path) }
    /// Still image used for thumbnails, the static desktop picture and the lock screen.
    var posterURL: URL { kind == .still ? fileURL : URL(fileURLWithPath: path + ".poster.jpg") }
}

enum Prefs {
    private static var d: UserDefaults { .standard }

    static func key(_ name: String) -> String {
        (d.string(forKey: "apiKey.\(name)") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isEnabled(_ provider: String) -> Bool {
        d.object(forKey: "enabled.\(provider)") == nil ? true : d.bool(forKey: "enabled.\(provider)")
    }
    static var pauseOnBattery: Bool { d.bool(forKey: "pauseOnBattery") }
    static var hideDockIcon: Bool { d.bool(forKey: "hideDockIcon") }
}
