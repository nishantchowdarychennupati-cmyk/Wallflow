import Foundation

/// Which slice of the catalog a Discover screen shows.
struct Feed: Hashable {
    var kind: WallpaperKind
    var provider: String? = nil   // restrict to one provider (e.g. "Bing Daily")
}

/// Searches every enabled provider in parallel and merges the results into one infinite feed.
@MainActor
final class Catalog: ObservableObject {
    @Published private(set) var items: [Wallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errors: [String] = []
    @Published private(set) var exhausted = false
    @Published var query = ""
    @Published var filters = SearchFilters() {
        didSet {
            var a = oldValue, b = filters
            a.seed = ""; b.seed = ""
            if a != b { reload(newSeed: false) }
        }
    }
    private(set) var feed = Feed(kind: .still)

    private var page = 1
    private var seen = Set<String>()
    private var task: Task<Void, Never>?
    private var settingsSignature = ""
    private var settingsObserver: NSObjectProtocol?
    private var debounce: Task<Void, Never>?

    init() {
        settingsSignature = Self.signature()
        // Reload automatically when API keys or enabled sources change in Settings.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settingsMayHaveChanged() }
        }
    }

    var activeProviders: [WallpaperProvider] {
        Providers.all.filter { p in
            p.supportedKinds.contains(feed.kind) && p.isActive && (feed.provider == nil || feed.provider == p.name)
        }
    }

    func show(_ feed: Feed) {
        guard feed != self.feed || items.isEmpty else { return }
        self.feed = feed
        reload()
    }

    func reload(newSeed: Bool = true) {
        task?.cancel()
        if newSeed { filters.seed = SearchFilters.newSeed() } // didSet ignores seed-only changes below
        items = []; errors = []; seen = []
        page = 1; exhausted = false; isLoading = false
        loadMore()
    }

    func loadMore() {
        guard !isLoading, !exhausted else { return }
        let providers = activeProviders
        guard !providers.isEmpty else { exhausted = true; return }
        isLoading = true
        let (text, kind, page, filters) = (query.trimmingCharacters(in: .whitespaces), feed.kind, page, filters)

        task = Task {
            let (batches, errs) = await Self.fetch(providers, text: text, kind: kind, page: page, filters: filters)
            guard !Task.isCancelled else { return }
            var merged = Self.interleave(batches)
            if filters.sort == .random { merged.shuffle() }
            let fresh = merged.filter { seen.insert($0.id).inserted }
            items += fresh
            errors = errs
            self.page += 1
            exhausted = fresh.isEmpty
            isLoading = false
        }
    }

    /// One-shot search used by auto-rotate.
    static func fetch(_ providers: [WallpaperProvider], text: String, kind: WallpaperKind, page: Int,
                      filters: SearchFilters) async -> ([[Wallpaper]], [String]) {
        var batches: [[Wallpaper]] = []
        var errs: [String] = []
        await withTaskGroup(of: (String, Result<[Wallpaper], Error>).self) { group in
            for provider in providers {
                group.addTask {
                    do { return (provider.name, .success(try await provider.search(text, kind: kind, page: page, filters: filters))) }
                    catch { return (provider.name, .failure(error)) }
                }
            }
            for await (name, result) in group {
                switch result {
                case .success(let batch): batches.append(batch)
                case .failure(let error): errs.append("\(name): \(error.localizedDescription)")
                }
            }
        }
        return (batches, errs)
    }

    private static func signature() -> String {
        Providers.all.map { "\($0.name)=\(Prefs.isEnabled($0.name)):\(Prefs.key($0.name))" }.joined(separator: "|")
    }

    private func settingsMayHaveChanged() {
        let sig = Self.signature()
        guard sig != settingsSignature else { return }
        settingsSignature = sig
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { reload() }
        }
    }

    /// Mix sources together so one provider doesn't dominate the top of the grid.
    static func interleave(_ batches: [[Wallpaper]]) -> [Wallpaper] {
        var out: [Wallpaper] = []
        let longest = batches.map(\.count).max() ?? 0
        for i in 0..<longest { for batch in batches where i < batch.count { out.append(batch[i]) } }
        return out
    }
}
