import SwiftUI

struct DiscoverView: View {
    let feed: Feed
    @EnvironmentObject var catalog: Catalog
    @State private var selected: Wallpaper?

    private var isDaily: Bool { feed.provider == "Bing Daily" }
    private var title: String {
        if isDaily { return "Wallpaper of the Day" }
        if let p = feed.provider { return feed.kind == .live ? "\(p) Videos" : p }
        return feed.kind == .still ? "4K Wallpapers" : "Live Wallpapers"
    }

    private var topics: [String] {
        feed.kind == .still
            ? ["Nature", "Space", "Mountains", "City", "Abstract", "Minimal", "Dark", "Ocean", "Anime", "Cars",
               "Architecture", "Forest", "Gradient", "Landscape", "Neon", "Sunset", "Aerial", "Snow", "Desert", "Galaxy"]
            : ["Ocean waves", "Rain", "Clouds", "Space", "Fireplace", "Abstract loop", "Forest", "City night",
               "Aurora", "Snow", "Particles", "Underwater", "Timelapse", "Waterfall", "Neon", "Galaxy", "Drone", "Sunset"]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !isDaily {
                    topicChips
                    FilterBar(kind: feed.kind)
                }
                if catalog.activeProviders.isEmpty { setupHint }
                ForEach(catalog.errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
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
                    ContentUnavailableView("No wallpapers found",
                                           systemImage: "magnifyingglass",
                                           description: Text("Try another search, a lower resolution, or no colour filter."))
                }
            }
            .padding(20)
        }
        .navigationTitle(title)
        .searchable(text: $catalog.query, prompt: feed.kind == .still ? "Search millions of 4K wallpapers" : "Search live wallpapers")
        .onSubmit(of: .search) { catalog.reload() }
        .toolbar {
            Button { catalog.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r")
        }
        .task(id: feed) {
            if isDaily { catalog.query = "" }
            catalog.show(feed)
        }
        .sheet(item: $selected) { WallpaperDetailView(wallpaper: $0) }
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(topics, id: \.self) { topic in
                    Button(topic) {
                        catalog.query = catalog.query == topic ? "" : topic
                        catalog.reload()
                    }
                    .buttonStyle(.bordered)
                    .tint(catalog.query == topic ? .accentColor : nil)
                }
            }
        }
    }

    private var setupHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(feed.kind == .live ? "Add a free API key to unlock live wallpapers" : "This source is turned off or needs a key")
                .font(.headline)
            Text(feed.kind == .live
                 ? "Live wallpapers come from Pexels and Pixabay, which together have hundreds of thousands of free HD and 4K videos. Each key is free and takes about a minute to get."
                 : "Turn it on or add its free key in Settings › Sources.")
                .foregroundStyle(.secondary)
            SettingsLink { Text("Open Settings") }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Resolution, sort and colour filters.
struct FilterBar: View {
    let kind: WallpaperKind
    @EnvironmentObject var catalog: Catalog

    private let swatches: [PaletteColor: Color] = [
        .red: .red, .orange: .orange, .yellow: .yellow, .green: .green, .teal: .teal,
        .blue: .blue, .purple: .purple, .pink: .pink, .black: .black, .white: .white,
    ]

    var body: some View {
        HStack(spacing: 16) {
            Picker("Resolution", selection: $catalog.filters.minResolution) {
                ForEach(MinResolution.allCases) { Text($0.label).tag($0) }
            }
            .frame(width: 190)
            Picker("Sort", selection: $catalog.filters.sort) {
                ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            if kind == .still {
                HStack(spacing: 5) {
                    ForEach(PaletteColor.allCases) { c in
                        Circle()
                            .fill(swatches[c] ?? .gray)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(catalog.filters.color == c ? 0.9 : 0.2),
                                                     lineWidth: catalog.filters.color == c ? 2.5 : 1))
                            .help(c.rawValue.capitalized)
                            .onTapGesture { catalog.filters.color = catalog.filters.color == c ? nil : c }
                    }
                    if catalog.filters.color != nil {
                        Button { catalog.filters.color = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
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
            if hovering && wallpaper.kind == .live {
                LoopingVideoView(url: wallpaper.previewURL).transition(.opacity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .opacity(hovering ? 1 : 0.6)
            VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    FavoriteButton(wallpaper: wallpaper).opacity(hovering || library.isFavorite(wallpaper.id) ? 1 : 0)
                }
                Spacer()
                HStack(spacing: 6) {
                    if wallpaper.kind == .live { Badge(text: "LIVE", systemImage: "play.fill") }
                    if wallpaper.width >= 3840 { Badge(text: wallpaper.width >= 5120 ? "5K" : "4K", systemImage: "sparkles") }
                    if library.item(id: wallpaper.id) != nil { Badge(text: "SAVED", systemImage: "checkmark") }
                    Spacer()
                    Text(hovering ? wallpaper.title : wallpaper.source)
                        .font(.caption2).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
            }
            .padding(8)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: 8, y: 4)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

/// Heart button: saves the wallpaper to the library (if needed) and marks it as a favorite.
struct FavoriteButton: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var library: Library

    var body: some View {
        let isFav = library.isFavorite(wallpaper.id)
        Button {
            if isFav { library.toggleFavorite(wallpaper.id); return }
            Task {
                if (try? await library.download(wallpaper)) != nil, !library.isFavorite(wallpaper.id) {
                    library.toggleFavorite(wallpaper.id)
                }
            }
        } label: {
            Group {
                if library.inFlight.contains(wallpaper.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .foregroundStyle(isFav ? .pink : .white)
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from Favorites" : "Save to Favorites")
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
