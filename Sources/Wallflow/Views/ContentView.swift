import SwiftUI

enum SidebarItem: Hashable {
    case discover(Feed)
    case library
    case favorites
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .discover(Feed(kind: .still))

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Discover") {
                    Label("4K Wallpapers", systemImage: "photo").tag(SidebarItem.discover(Feed(kind: .still)))
                    Label("Live Wallpapers", systemImage: "play.rectangle").tag(SidebarItem.discover(Feed(kind: .live)))
                    Label("Wallpaper of the Day", systemImage: "sun.max").tag(SidebarItem.discover(Feed(kind: .still, provider: "Bing Daily")))
                }
                Section("Sources") {
                    ForEach(Providers.all.indices, id: \.self) { i in
                        let p = Providers.all[i]
                        if p.name != "Bing Daily" {
                            ForEach(p.supportedKinds.sorted { $0.rawValue > $1.rawValue }) { kind in
                                Label("\(p.name)\(p.supportedKinds.count > 1 ? (kind == .live ? " Videos" : " Photos") : "")",
                                      systemImage: kind == .live ? "film" : "globe")
                                    .tag(SidebarItem.discover(Feed(kind: kind, provider: p.name)))
                            }
                        }
                    }
                }
                Section("Mine") {
                    Label("Library", systemImage: "square.stack").tag(SidebarItem.library)
                    Label("Favorites", systemImage: "heart").tag(SidebarItem.favorites)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch selection ?? .discover(Feed(kind: .still)) {
            case .discover(let feed): DiscoverView(feed: feed)
            case .library: LibraryView(favoritesOnly: false)
            case .favorites: LibraryView(favoritesOnly: true)
            }
        }
    }
}
