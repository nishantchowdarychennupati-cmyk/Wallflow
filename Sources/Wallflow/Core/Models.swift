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
    var caption: String? = nil

    var resolutionLabel: String {
        let tag = width >= 5120 ? " · 5K" : width >= 3840 ? " · 4K" : ""
        return "\(width)×\(height)\(tag)"
    }
    var title: String { caption ?? author.map { "\(source) · \($0)" } ?? source }
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

// MARK: - Search filters

enum MinResolution: Int, CaseIterable, Identifiable {
    case hd = 1920, qhd = 2560, uhd = 3840, fiveK = 5120
    var id: Int { rawValue }
    var width: Int { rawValue }
    var height: Int { rawValue * 9 / 16 }
    var label: String {
        switch self {
        case .hd: return "Full HD+"
        case .qhd: return "1440p+"
        case .uhd: return "4K+"
        case .fiveK: return "5K+"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case popular, latest, random
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PaletteColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, black, white
    var id: String { rawValue }
    /// Hex values from Wallhaven's colour palette (also accepted by Pexels).
    var hex: String {
        switch self {
        case .red: return "cc0000"
        case .orange: return "ff9900"
        case .yellow: return "ffff00"
        case .green: return "669900"
        case .teal: return "66cccc"
        case .blue: return "0066cc"
        case .purple: return "663399"
        case .pink: return "ea4c88"
        case .black: return "000000"
        case .white: return "ffffff"
        }
    }
    var unsplashName: String { self == .pink ? "magenta" : rawValue }
}

struct SearchFilters: Equatable {
    var minResolution: MinResolution = .uhd
    var sort: SortOrder = .popular
    var color: PaletteColor? = nil
    var seed: String = SearchFilters.newSeed()

    static func newSeed() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)) }
}

// MARK: - Preferences

enum Prefs {
    private static var d: UserDefaults { .standard }

    static func key(_ name: String) -> String {
        (d.string(forKey: "apiKey.\(name)") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isEnabled(_ provider: String) -> Bool { bool("enabled.\(provider)", default: true) }
    static var pauseOnBattery: Bool { d.bool(forKey: "pauseOnBattery") }
    static var hideDockIcon: Bool { d.bool(forKey: "hideDockIcon") }

    // Live playback
    static var playbackRate: Double { let v = d.double(forKey: "playbackRate"); return v == 0 ? 1 : v }
    static var videoFill: Bool { bool("videoFill", default: true) }
    static var dimLevel: Double { d.double(forKey: "dimLevel") }

    // Auto-rotate
    static var rotateMinutes: Int { d.integer(forKey: "rotateMinutes") }   // 0 = off
    static var rotateSource: String { d.string(forKey: "rotateSource") ?? "library" } // library | favorites | online
    static var rotateQuery: String { d.string(forKey: "rotateQuery") ?? "nature" }
    static var rotateKind: String { d.string(forKey: "rotateKind") ?? "any" } // any | still | live

    private static func bool(_ key: String, default value: Bool) -> Bool {
        d.object(forKey: key) == nil ? value : d.bool(forKey: key)
    }
}
