import Foundation

/// pexels.com — free photos AND free HD/4K stock videos (great live wallpapers). Needs a free key.
struct PexelsProvider: WallpaperProvider {
    let name = "Pexels"
    let supportedKinds: Set<WallpaperKind> = [.still, .live]
    let signupURL: URL? = URL(string: "https://www.pexels.com/api/new/")
    let needsKey = true

    private struct PhotoResponse: Decodable {
        let photos: [Photo]
        struct Photo: Decodable {
            let id: Int
            let width: Int
            let height: Int
            let url: String
            let photographer: String
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

    func search(_ text: String, kind: WallpaperKind, page: Int) async throws -> [Wallpaper] {
        let headers = ["Authorization": Prefs.key(name)]
        switch kind {
        case .still:
            let url = text.isEmpty
                ? URL.build("https://api.pexels.com/v1/curated", [("per_page", "40"), ("page", String(page))])
                : URL.build("https://api.pexels.com/v1/search", [
                    ("query", text), ("orientation", "landscape"), ("size", "large"),
                    ("per_page", "40"), ("page", String(page)),
                ])
            let response = try await HTTP.get(url, headers: headers, as: PhotoResponse.self)
            return response.photos.compactMap { p in
                guard p.width >= p.height,
                      let thumb = (p.src["landscape"] ?? p.src["medium"]).flatMap(URL.init(string:)),
                      let preview = (p.src["large2x"] ?? p.src["large"]).flatMap(URL.init(string:)),
                      let full = p.src["original"].flatMap(URL.init(string:)) else { return nil }
                return Wallpaper(id: "pexels-p-\(p.id)", source: name, kind: .still,
                                 thumbnailURL: thumb, previewURL: preview, fullURL: full,
                                 width: p.width, height: p.height, author: p.photographer,
                                 pageURL: URL(string: p.url))
            }
        case .live:
            let url = text.isEmpty
                ? URL.build("https://api.pexels.com/videos/popular", [
                    ("min_width", "1920"), ("per_page", "40"), ("page", String(page)),
                ])
                : URL.build("https://api.pexels.com/videos/search", [
                    ("query", text), ("orientation", "landscape"), ("size", "large"),
                    ("per_page", "40"), ("page", String(page)),
                ])
            let response = try await HTTP.get(url, headers: headers, as: VideoResponse.self)
            return response.videos.compactMap { v in
                guard v.width >= v.height,
                      let full = Self.pick(v.video_files, maxWidth: 3840).flatMap({ URL(string: $0.link) }),
                      let preview = Self.pick(v.video_files, maxWidth: 1280).flatMap({ URL(string: $0.link) }),
                      let thumb = URL(string: v.image) else { return nil }
                return Wallpaper(id: "pexels-v-\(v.id)", source: name, kind: .live,
                                 thumbnailURL: thumb, previewURL: preview, fullURL: full,
                                 width: v.width, height: v.height, author: v.user.name,
                                 pageURL: URL(string: v.url))
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
