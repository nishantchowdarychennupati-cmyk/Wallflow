import Foundation

/// pexels.com — free photos AND free HD/4K stock videos (great live wallpapers). Needs a free key.
struct PexelsProvider: WallpaperProvider {
    let name = "Pexels"
    let supportedKinds: Set<WallpaperKind> = [.still, .live]
    let signupURL: URL? = URL(string: "https://www.pexels.com/api/new/")
    let needsKey = true
    let blurb = "Photos and 4K stock videos — the best source for live wallpapers."

    private struct PhotoResponse: Decodable {
        let photos: [Photo]
        struct Photo: Decodable {
            let id: Int
            let width: Int
            let height: Int
            let url: String
            let photographer: String
            let alt: String?
            let src: [String: String]
        }
    }

    private struct VideoResponse: Decodable {
        let videos: [Video]
        struct Video: Decodable {
            let id: Int
            let width: Int
            let height: Int
            let url: String
            let image: String
            let user: User
            let video_files: [File]
        }
        struct User: Decodable { let name: String }
        struct File: Decodable {
            let file_type: String
            let width: Int?
            let height: Int?
            let link: String
        }
    }

    func search(_ text: String, kind: WallpaperKind, page: Int, filters: SearchFilters) async throws -> [Wallpaper] {
        let headers = ["Authorization": Prefs.key(name)]
        // Pexels has no random/latest ordering; "random" jumps to a random page instead.
        let effectivePage = filters.sort == .random ? Int.random(in: 1...40) : page
        switch kind {
        case .still:
            let url = text.isEmpty && filters.color == nil
                ? URL.build("https://api.pexels.com/v1/curated", [("per_page", "40"), ("page", String(effectivePage))])
                : URL.build("https://api.pexels.com/v1/search", [
                    ("query", text.isEmpty ? "wallpaper" : text), ("orientation", "landscape"), ("size", "large"),
                    ("color", filters.color?.hex), ("per_page", "40"), ("page", String(effectivePage)),
                ])
            let response = try await HTTP.get(url, headers: headers, as: PhotoResponse.self)
            return response.photos.compactMap { p in
                guard p.width >= p.height, p.width >= filters.minResolution.width,
                      let thumb = (p.src["landscape"] ?? p.src["medium"]).flatMap(URL.init(string:)),
                      let preview = (p.src["large2x"] ?? p.src["large"]).flatMap(URL.init(string:)),
                      let full = p.src["original"].flatMap(URL.init(string:)) else { return nil }
                var w = Wallpaper(id: "pexels-p-\(p.id)", source: name, kind: .still,
                                  thumbnailURL: thumb, previewURL: preview, fullURL: full,
                                  width: p.width, height: p.height, author: p.photographer,
                                  pageURL: URL(string: p.url))
                if let alt = p.alt, !alt.isEmpty { w.caption = alt }
                return w
            }
        case .live:
            let url = text.isEmpty
                ? URL.build("https://api.pexels.com/videos/popular", [
                    ("min_width", String(filters.minResolution.width)), ("per_page", "40"), ("page", String(effectivePage)),
                ])
                : URL.build("https://api.pexels.com/videos/search", [
                    ("query", text), ("orientation", "landscape"), ("size", filters.minResolution.width >= 3840 ? "large" : "medium"),
                    ("per_page", "40"), ("page", String(effectivePage)),
                ])
            let response = try await HTTP.get(url, headers: headers, as: VideoResponse.self)
            return response.videos.compactMap { v in
                guard v.width >= v.height,
                      let best = Self.pick(v.video_files, maxWidth: 4096),
                      (best.width ?? 0) >= filters.minResolution.width,
                      let full = URL(string: best.link),
                      let preview = Self.pick(v.video_files, maxWidth: 1280).flatMap({ URL(string: $0.link) }),
                      let thumb = URL(string: v.image) else { return nil }
                return Wallpaper(id: "pexels-v-\(v.id)", source: name, kind: .live,
                                 thumbnailURL: thumb, previewURL: preview, fullURL: full,
                                 width: best.width ?? v.width, height: best.height ?? v.height,
                                 author: v.user.name, pageURL: URL(string: v.url))
            }
        }
    }

    /// Largest landscape MP4 rendition that is not wider than `maxWidth`.
    private static func pick(_ files: [VideoResponse.File], maxWidth: Int) -> VideoResponse.File? {
        let mp4 = files.filter { $0.file_type == "video/mp4" && ($0.width ?? 0) >= ($0.height ?? 0) }
        let fitting = mp4.filter { ($0.width ?? 0) <= maxWidth }
        return fitting.max { ($0.width ?? 0) < ($1.width ?? 0) }
            ?? mp4.min { ($0.width ?? 0) < ($1.width ?? 0) }
    }
}
