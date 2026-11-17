import Foundation

/// unsplash.com — high quality free photography (originals are usually 4K–8K). Needs a free "Access Key".
struct UnsplashProvider: WallpaperProvider {
    let name = "Unsplash"
    let supportedKinds: Set<WallpaperKind> = [.still]
    let signupURL: URL? = URL(string: "https://unsplash.com/oauth/applications")
    let needsKey = true
    let blurb = "Professional photography, originals usually 4K–8K."

    private struct Photo: Decodable {
        let id: String
        let width: Int
        let height: Int
        let urls: [String: String]
        let links: [String: String]
        let user: User
        struct User: Decodable { let name: String }
    }
    private struct SearchResponse: Decodable { let results: [Photo] }

    func search(_ text: String, kind: WallpaperKind, page: Int, filters: SearchFilters) async throws -> [Wallpaper] {
        let headers = ["Authorization": "Client-ID \(Prefs.key(name))", "Accept-Version": "v1"]
        var photos: [Photo]
        if text.isEmpty && filters.color == nil {
            let url = URL.build("https://api.unsplash.com/topics/wallpapers/photos", [
                ("orientation", "landscape"), ("per_page", "30"), ("page", String(page)),
                ("order_by", filters.sort == .latest ? "latest" : "popular"),
            ])
            photos = try await HTTP.get(url, headers: headers, as: [Photo].self)
        } else {
            let url = URL.build("https://api.unsplash.com/search/photos", [
                ("query", text.isEmpty ? "wallpaper" : text), ("orientation", "landscape"),
                ("per_page", "30"), ("page", String(page)),
                ("order_by", filters.sort == .latest ? "latest" : "relevant"),
                ("color", filters.color?.unsplashName),
            ])
            photos = try await HTTP.get(url, headers: headers, as: SearchResponse.self).results
        }
        if filters.sort == .random { photos.shuffle() }
        return photos.compactMap { p in
            guard p.width >= filters.minResolution.width,
                  let thumb = p.urls["small"].flatMap(URL.init(string:)),
                  let preview = p.urls["regular"].flatMap(URL.init(string:)),
                  let raw = p.urls["raw"] ?? p.urls["full"],
                  let full = URL(string: raw + (raw.contains("?") ? "&" : "?") + "fm=jpg&q=90") else { return nil }
            var w = Wallpaper(id: "unsplash-\(p.id)", source: name, kind: .still,
                              thumbnailURL: thumb, previewURL: preview, fullURL: full,
                              width: p.width, height: p.height, author: p.user.name,
                              pageURL: p.links["html"].flatMap(URL.init(string:)))
            w.downloadPing = p.links["download_location"].flatMap(URL.init(string:))
            return w
        }
    }
}
