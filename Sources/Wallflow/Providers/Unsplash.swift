import Foundation

/// unsplash.com — high quality free photography. Needs a free "Access Key".
struct UnsplashProvider: WallpaperProvider {
    let name = "Unsplash"
    let supportedKinds: Set<WallpaperKind> = [.still]
    let signupURL: URL? = URL(string: "https://unsplash.com/oauth/applications")
    let needsKey = true

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

    func search(_ text: String, kind: WallpaperKind, page: Int) async throws -> [Wallpaper] {
        let headers = ["Authorization": "Client-ID \(Prefs.key(name))", "Accept-Version": "v1"]
        let photos: [Photo]
        if text.isEmpty {
            let url = URL.build("https://api.unsplash.com/topics/wallpapers/photos", [
                ("orientation", "landscape"), ("per_page", "30"), ("page", String(page)),
            ])
            photos = try await HTTP.get(url, headers: headers, as: [Photo].self)
        } else {
            let url = URL.build("https://api.unsplash.com/search/photos", [
                ("query", text), ("orientation", "landscape"), ("per_page", "30"), ("page", String(page)),
            ])
            photos = try await HTTP.get(url, headers: headers, as: SearchResponse.self).results
        }
        return photos.compactMap { p in
            guard let thumb = p.urls["small"].flatMap(URL.init(string:)),
                  let preview = p.urls["regular"].flatMap(URL.init(string:)),
                  let full = p.urls["full"].flatMap(URL.init(string:)) else { return nil }
            var w = Wallpaper(id: "unsplash-\(p.id)", source: name, kind: .still,
                              thumbnailURL: thumb, previewURL: preview, fullURL: full,
                              width: p.width, height: p.height, author: p.user.name,
                              pageURL: p.links["html"].flatMap(URL.init(string:)))
            w.downloadPing = p.links["download_location"].flatMap(URL.init(string:))
            return w
        }
    }
}
