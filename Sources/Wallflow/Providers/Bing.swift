import Foundation

/// Bing "Wallpaper of the Day" — a hand-picked 4K (3840×2160) photo every day. No key needed.
struct BingProvider: WallpaperProvider {
    let name = "Bing Daily"
    let supportedKinds: Set<WallpaperKind> = [.still]
    let signupURL: URL? = nil
    let needsKey = false
    let blurb = "A new hand-picked 4K photo every day."

    private struct Response: Decodable {
        let images: [Image]
        struct Image: Decodable {
            let urlbase: String
            let copyright: String
            let copyrightlink: String?
            let title: String?
            let startdate: String
        }
    }

    func search(_ text: String, kind: WallpaperKind, page: Int, filters: SearchFilters) async throws -> [Wallpaper] {
        // Bing exposes roughly the last 16 days; it can't be searched or colour-filtered.
        guard text.isEmpty, filters.color == nil, page <= 2, filters.minResolution.width <= 3840 else { return [] }
        let url = URL.build("https://www.bing.com/HPImageArchive.aspx", [
            ("format", "js"), ("idx", page == 1 ? "0" : "8"), ("n", "8"), ("mkt", "en-US"),
        ])
        let response = try await HTTP.get(url, as: Response.self)
        return response.images.compactMap { img in
            guard let full = URL(string: "https://www.bing.com\(img.urlbase)_UHD.jpg"),
                  let thumb = URL(string: "https://www.bing.com\(img.urlbase)_800x480.jpg") else { return nil }
            let author = img.copyright.components(separatedBy: "(©").last.map { "©" + $0.trimmingCharacters(in: CharacterSet(charactersIn: ") ")) }
            var w = Wallpaper(id: "bing-\(img.startdate)", source: name, kind: .still,
                              thumbnailURL: thumb, previewURL: full, fullURL: full,
                              width: 3840, height: 2160, author: author,
                              pageURL: img.copyrightlink.flatMap(URL.init(string:)))
            w.caption = img.title ?? img.copyright.components(separatedBy: " (").first
            return w
        }
    }
}
