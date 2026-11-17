import SwiftUI

struct DiscoverView: View {
    let kind: WallpaperKind
    @EnvironmentObject var catalog: Catalog
    @State private var selected: Wallpaper?

    private var topics: [String] {
        kind == .still
            ? ["Nature", "Space", "Mountains", "City", "Abstract", "Minimal", "Dark", "Ocean", "Anime", "Cars", "Architecture", "Forest"]
            : ["Ocean waves", "Rain", "Clouds", "Space", "Fireplace", "Abstract loop", "Forest", "City night", "Aurora", "Snow", "Particles", "Underwater"]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topicChips
                if catalog.activeProviders.isEmpty { setupHint }
                ForEach(catalog.errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(catalog.items) { wallpaper in
                        RemoteCard(wallpaper: wallpaper)
                            .onTapGesture { selected = wallpaper }
                            .onAppear { if wallpaper.id == catalog.items.last?.id { catalog.loadMore() } }
                    }
                }
                if catalog.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if catalog.exhausted && !catalog.items.isEmpty {
                    Text("That's everything for this search.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                } else if catalog.items.isEmpty && !catalog.activeProviders.isEmpty && catalog.exhausted {
                    ContentUnavailableView.search(text: catalog.query)
                }
            }
            .padding(20)
        }
        .navigationTitle(kind.title)
        .searchable(text: $catalog.query, prompt: kind == .still ? "Search millions of wallpapers" : "Search live wallpapers")
        .onSubmit(of: .search) { catalog.reload() }
        .toolbar {
            Button { catalog.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
        .task(id: kind) { catalog.show(kind: kind) }
        .sheet(item: $selected) { WallpaperDetailView(wallpaper: $0) }
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(topics, id: \.self) { topic in
                    Button(topic) { catalog.query = topic; catalog.reload() }
                        .buttonStyle(.bordered)
                        .tint(catalog.query == topic ? .accentColor : nil)
                }
            }
        }
    }

    private var setupHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .live ? "Add a free API key to unlock live wallpapers" : "All wallpaper sources are turned off")
                .font(.headline)
            Text(kind == .live
                 ? "Live wallpapers come from Pexels and Pixabay, which together have hundreds of thousands of free HD and 4K videos. Each key is free and takes about a minute to get."
                 : "Turn on at least one source in Settings.")
                .foregroundStyle(.secondary)
            SettingsLink { Text("Open Settings") }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RemoteCard: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var library: Library
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.secondary.opacity(0.15)
            AsyncImage(url: wallpaper.thumbnailURL, transaction: .init(animation: .easeIn(duration: 0.2))) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .opacity(hovering ? 1 : 0.6)
            HStack(spacing: 6) {
                if wallpaper.kind == .live { Badge(text: "LIVE", systemImage: "play.fill") }
                if library.item(id: wallpaper.id) != nil { Badge(text: "SAVED", systemImage: "checkmark") }
                Spacer()
                Text("\(wallpaper.source) · \(wallpaper.resolutionLabel)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.9))
            }
            .padding(8)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

struct Badge: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
