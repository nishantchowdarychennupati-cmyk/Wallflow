import Foundation

/// Searches every enabled provider in parallel and merges the results into one infinite feed.
@MainActor
final class Catalog: ObservableObject {
    @Published private(set) var items: [Wallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errors: [String] = []
    @Published private(set) var exhausted = false
    @Published var query = ""
    private(set) var kind: WallpaperKind = .still

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

    var activeProviders: [WallpaperProvider] {
        Providers.all.filter { $0.supportedKinds.contains(kind) && $0.isActive }
    }

    func show(kind: WallpaperKind) {
        guard kind != self.kind || items.isEmpty else { return }
        self.kind = kind
        reload()
    }

    func reload() {
        task?.cancel()
        items = []; errors = []; seen = []
        page = 1; exhausted = false; isLoading = false
        loadMore()
    }

    func loadMore() {
        guard !isLoading, !exhausted else { return }
        let providers = activeProviders
        guard !providers.isEmpty else { exhausted = true; return }
        isLoading = true
        let (text, kind, page) = (query.trimmingCharacters(in: .whitespaces), kind, page)

        task = Task {
            var batches: [[Wallpaper]] = []
            var errs: [String] = []
            await withTaskGroup(of: (String, Result<[Wallpaper], Error>).self) { group in
                for provider in providers {
                    group.addTask {
                        do { return (provider.name, .success(try await provider.search(text, kind: kind, page: page))) }
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
            guard !Task.isCancelled else { return }
            let fresh = Self.interleave(batches).filter { seen.insert($0.id).inserted }
            items += fresh
            errors = errs
            self.page += 1
            exhausted = fresh.isEmpty
            isLoading = false
        }
    }

    /// Mix sources together so one provider doesn't dominate the top of the grid.
    private static func interleave(_ batches: [[Wallpaper]]) -> [Wallpaper] {
        var out: [Wallpaper] = []
        let longest = batches.map(\.count).max() ?? 0
        for i in 0..<longest { for batch in batches where i < batch.count { out.append(batch[i]) } }
        return out
    }
}
