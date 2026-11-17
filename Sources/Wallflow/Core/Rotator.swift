import Foundation

/// Automatically changes the wallpaper on a schedule — from the library, favorites, or fresh 4K
/// wallpapers pulled from the internet for a search term.
@MainActor
final class Rotator: ObservableObject {
    static let shared = Rotator()

    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?
    private var timer: Timer?
    private var scheduledMinutes = -1
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Rotator.shared.reschedule() }
        }
    }

    func reschedule() {
        let minutes = Prefs.rotateMinutes
        guard minutes != scheduledMinutes else { return }
        scheduledMinutes = minutes
        timer?.invalidate()
        timer = nil
        guard minutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { _ in
            Task { @MainActor in await Rotator.shared.next() }
        }
    }

    /// Switch to the next wallpaper right now.
    func next() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let library = Library.shared
        let engine = WallpaperEngine.shared
        let kindFilter: WallpaperKind? = WallpaperKind(rawValue: Prefs.rotateKind)

        do {
            switch Prefs.rotateSource {
            case "online":
                let kind = kindFilter ?? .still
                var filters = SearchFilters()
                filters.sort = .random
                filters.minResolution = kind == .live ? .hd : .uhd
                let providers = Providers.all.filter { $0.supportedKinds.contains(kind) && $0.isActive && $0.name != "Bing Daily" }
                let (batches, errors) = await Catalog.fetch(providers, text: Prefs.rotateQuery, kind: kind,
                                                            page: Int.random(in: 1...3), filters: filters)
                guard let pick = batches.flatMap({ $0 }).filter({ !engine.isCurrent($0.id) }).randomElement() else {
                    lastError = errors.first ?? "No results for “\(Prefs.rotateQuery)”"
                    return
                }
                try engine.apply(try await library.download(pick))
            default:
                let pool = library.items.filter { item in
                    (Prefs.rotateSource != "favorites" || library.isFavorite(item.id))
                        && (kindFilter == nil || item.kind == kindFilter)
                        && !engine.isCurrent(item.id)
                }
                guard let pick = pool.randomElement() else {
                    lastError = "Nothing to rotate to yet. Save a few wallpapers first."
                    return
                }
                try engine.apply(pick)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
