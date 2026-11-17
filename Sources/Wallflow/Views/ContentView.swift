import SwiftUI

enum SidebarItem: Hashable {
    case discover(WallpaperKind)
    case library
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .discover(.still)

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Discover") {
                    Label("Wallpapers", systemImage: "photo").tag(SidebarItem.discover(.still))
                    Label("Live Wallpapers", systemImage: "play.rectangle").tag(SidebarItem.discover(.live))
                }
                Section("Mine") {
                    Label("Library", systemImage: "square.stack").tag(SidebarItem.library)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .discover(.still) {
            case .discover(let kind): DiscoverView(kind: kind)
            case .library: LibraryView()
            }
        }
    }
}
