import Foundation

enum ProviderError: LocalizedError {
    case badResponse
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected server response"
        case .http(401), .http(403): return "API key rejected (check Settings)"
        case .http(429): return "Rate limit reached, try again later"
        case .http(let code): return "Server error \(code)"
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    static func get<T: Decodable>(_ url: URL, headers: [String: String] = [:], as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("Wallflow/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension URL {
    static func build(_ base: String, _ params: [(String, String?)]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = params.compactMap { pair in pair.1.map { URLQueryItem(name: pair.0, value: $0) } }
        return c.url!
    }
}

protocol WallpaperProvider {
    var name: String { get }
    var supportedKinds: Set<WallpaperKind> { get }
    var signupURL: URL? { get }
    var needsKey: Bool { get }
    var blurb: String { get }
    func search(_ text: String, kind: WallpaperKind, page: Int, filters: SearchFilters) async throws -> [Wallpaper]
}

extension WallpaperProvider {
    var isConfigured: Bool { !needsKey || !Prefs.key(name).isEmpty }
    var isActive: Bool { isConfigured && Prefs.isEnabled(name) }
}

enum Providers {
    static let all: [WallpaperProvider] = [
        WallhavenProvider(), UnsplashProvider(), PexelsProvider(), PixabayProvider(), BingProvider(),
    ]
    static func named(_ name: String) -> WallpaperProvider? { all.first { $0.name == name } }
}
