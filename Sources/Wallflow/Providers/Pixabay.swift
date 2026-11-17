import Foundation

/// pixabay.com — free stock videos (used for live wallpapers). Needs a free key.
struct PixabayProvider: WallpaperProvider {
    let name = "Pixabay"
    let supportedKinds: Set<WallpaperKind> = [.live]
    let signupURL: URL? = URL(string: "https://pixabay.com/api/docs/")
    let needsKey = true
    let blurb = "Free HD and 4K videos and animations for live wallpapers."

    private struct Response: Decodable {
        let hits: [Hit]
        struct Hit: Decodable {
            let id: Int
            let pageURL: String
            let user: String
            let tags: String?
            let picture_id: String?
            let videos: [String: Rendition]
        }
        struct Rendition: Decodable {
            let url: String
            let width: Int
            let height: Int
            let thumbnail: String?
        }
    }

    func search(_ text: String, kind: WallpaperKind, page: Int, filters: SearchFilters) async throws -> [Wallpaper] {
        let effectivePage = filters.sort == .random ? Int.random(in: 1...10) : page
        let url = URL.build("https://pixabay.com/api/videos/", [
            ("key", Prefs.key(name)),
            ("q", text.isEmpty ? nil : text),
            ("order", filters.sort == .latest ? "latest" : "popular"),
            ("safesearch", "true"),
            ("min_width", String(filters.minResolution.width)),
            ("per_page", "40"),
            ("page", String(effectivePage)),
        ])
        let response: Response
        do {
            response = try await HTTP.get(url, as: Response.self)
        } catch ProviderError.http(400) where effectivePage > 1 {
            return [] // Pixabay answers 400 once you page past the last result
        }
        return response.hits.compactMap { hit in
            let renditions = ["large", "medium", "small", "tiny"].compactMap { key -> Response.Rendition? in
                guard let r = hit.videos[key], !r.url.isEmpty else { return nil }
                return r
            }
            guard let best = renditions.first, best.width >= best.height,
                  let full = URL(string: best.url) else { return nil }
            let previewRendition = renditions.first { $0.width <= 1280 } ?? best
            let thumbString = renditions.compactMap(\.thumbnail).first(where: { !$0.isEmpty })
                ?? hit.picture_id.map { "https://i.vimeocdn.com/video/\($0)_640x360.jpg" }
            guard let preview = URL(string: previewRendition.url),
                  let thumb = thumbString.flatMap(URL.init(string:)) else { return nil }
            var w = Wallpaper(id: "pixabay-v-\(hit.id)", source: name, kind: .live,
                              thumbnailURL: thumb, previewURL: preview, fullURL: full,
                              width: best.width, height: best.height, author: hit.user,
                              pageURL: URL(string: hit.pageURL))
            if let tags = hit.tags, !tags.isEmpty { w.caption = tags.capitalized }
            return w
        }
    }
}
