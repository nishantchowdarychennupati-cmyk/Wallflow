import Foundation

/// wallhaven.cc — huge community wallpaper archive. Works without a key (SFW content).
struct WallhavenProvider: WallpaperProvider {
    let name = "Wallhaven"
    let supportedKinds: Set<WallpaperKind> = [.still]
    let signupURL: URL? = URL(string: "https://wallhaven.cc/settings/account")
    let needsKey = false

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

    func search(_ text: String, kind: WallpaperKind, page: Int) async throws -> [Wallpaper] {
        let key = Prefs.key(name)
        let url = URL.build("https://wallhaven.cc/api/v1/search", [
            ("q", text.isEmpty ? nil : text),
            ("categories", "111"),
            ("purity", "100"),
            ("sorting", text.isEmpty ? "toplist" : "relevance"),
            ("topRange", text.isEmpty ? "1y" : nil),
            ("atleast", "2560x1440"),
            ("ratios", "16x9,16x10,21x9"),
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
