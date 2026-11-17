import Foundation

/// wallhaven.cc — huge community wallpaper archive with hundreds of thousands of 4K+ images.
/// Works without a key (safe-for-work content only).
struct WallhavenProvider: WallpaperProvider {
    let name = "Wallhaven"
    let supportedKinds: Set<WallpaperKind> = [.still]
    let signupURL: URL? = URL(string: "https://wallhaven.cc/settings/account")
    let needsKey = false
    let blurb = "1M+ community wallpapers, huge 4K/5K/8K collection. No key needed."

    private struct Response: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let id: String
            let url: String
            let path: String
            let dimension_x: Int
            let dimension_y: Int
            let thumbs: [String: String]
        }
    }

    func search(_ text: String, kind: WallpaperKind, page: Int, filters: SearchFilters) async throws -> [Wallpaper] {
        let key = Prefs.key(name)
        let sorting: String
        switch filters.sort {
        case .popular: sorting = text.isEmpty ? "toplist" : "relevance"
        case .latest: sorting = "date_added"
        case .random: sorting = "random"
        }
        let url = URL.build("https://wallhaven.cc/api/v1/search", [
            ("q", text.isEmpty ? nil : text),
            ("categories", "111"),
            ("purity", "100"),
            ("sorting", sorting),
            ("topRange", sorting == "toplist" ? "1y" : nil),
            ("seed", sorting == "random" ? filters.seed : nil),
            ("atleast", "\(filters.minResolution.width)x\(filters.minResolution.height)"),
            ("ratios", "16x9,16x10,21x9,32x9"),
            ("colors", filters.color?.hex),
            ("page", String(page)),
            ("apikey", key.isEmpty ? nil : key),
        ])
        let response = try await HTTP.get(url, as: Response.self)
        return response.data.compactMap { item in
            guard let full = URL(string: item.path),
                  let thumb = URL(string: item.thumbs["large"] ?? item.thumbs["original"] ?? item.path) else { return nil }
            return Wallpaper(id: "wallhaven-\(item.id)", source: name, kind: .still,
                             thumbnailURL: thumb, previewURL: full, fullURL: full,
                             width: item.dimension_x, height: item.dimension_y,
                             author: nil, pageURL: URL(string: item.url))
        }
    }
}
