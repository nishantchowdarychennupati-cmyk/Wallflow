import ImageIO
import SwiftUI

struct LibraryView: View {
    let favoritesOnly: Bool
    @EnvironmentObject var library: Library
    @EnvironmentObject var engine: WallpaperEngine
    @State private var filter: WallpaperKind?
    @State private var importing = false
    @State private var lockScreenItem: LocalWallpaper?
    @State private var error: String?

    private var visible: [LocalWallpaper] {
        library.items.filter { (filter == nil || $0.kind == filter) && (!favoritesOnly || library.isFavorite($0.id)) }
    }

    var body: some View {
        ScrollView {
            if visible.isEmpty {
                ContentUnavailableView(favoritesOnly ? "No favorites yet" : "Your library is empty",
                                       systemImage: favoritesOnly ? "heart" : "square.stack",
                                       description: Text(favoritesOnly
                                                         ? "Click the heart on any wallpaper to keep it here."
                                                         : "Save wallpapers from Discover, or import your own images and videos."))
                    .padding(.top, 80)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(visible) { item in
                    LocalCard(item: item, isCurrent: engine.isCurrent(item.id))
                        .onTapGesture(count: 2) { apply(item) }
                        .contextMenu {
                            Button("Set as Wallpaper") { apply(item) }
                            if NSScreen.screens.count > 1 {
                                Menu("Set on Display") {
                                    ForEach(NSScreen.screens, id: \.wallflowKey) { screen in
                                        Button(screen.localizedName) { apply(item, to: screen) }
                                    }
                                }
                            }
                            Button(library.isFavorite(item.id) ? "Remove from Favorites" : "Add to Favorites") {
                                library.toggleFavorite(item.id)
                            }
                            if item.kind == .live {
                                Button("Use on Lock Screen (Experimental)…") { lockScreenItem = item }
                            }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }
                            Divider()
                            Button("Delete", role: .destructive) { library.remove(item) }
                        }
                }
            }
            .padding(20)
        }
        .navigationTitle(favoritesOnly ? "Favorites" : "Library")
        .navigationSubtitle("Double-click to apply · right-click for more")
        .toolbar {
            Picker("Show", selection: $filter) {
                Text("All").tag(WallpaperKind?.none)
                Text("Still").tag(WallpaperKind?.some(.still))
                Text("Live").tag(WallpaperKind?.some(.live))
            }
            .pickerStyle(.segmented)
            if engine.isLive {
                Button { engine.togglePause() } label: {
                    Label(engine.isPaused ? "Resume" : "Pause", systemImage: engine.isPaused ? "play.fill" : "pause.fill")
                }
            }
            Button { Task { await Rotator.shared.next() } } label: { Label("Next", systemImage: "forward.fill") }
                .help("Switch to the next wallpaper (uses your Auto-Rotate settings)")
            Button { importing = true } label: { Label("Import", systemImage: "plus") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await library.importFiles(urls) } }
        }
        .sheet(item: $lockScreenItem) { LockScreenSheet(item: $0) }
        .alert("Couldn't set wallpaper", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func apply(_ item: LocalWallpaper, to screen: NSScreen? = nil) {
        do { try engine.apply(item, to: screen) } catch { self.error = error.localizedDescription }
    }
}

struct LocalCard: View {
    let item: LocalWallpaper
    let isCurrent: Bool
    @EnvironmentObject var library: Library
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.secondary.opacity(0.15)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            if hovering && item.kind == .live { LoopingVideoView(url: item.fileURL) }
            if library.isFavorite(item.id) {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                    .padding(6).background(.ultraThinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
            HStack(spacing: 6) {
                if item.kind == .live { Badge(text: "LIVE", systemImage: "play.fill") }
                if isCurrent { Badge(text: "CURRENT", systemImage: "checkmark.circle.fill") }
                Spacer()
            }
            .padding(8)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: isCurrent ? 3 : 0))
        .help(item.title)
        .onHover { hovering = $0 }
        .task(id: item.id) { image = await Thumbnails.load(item.posterURL) }
    }
}

/// Small, cached thumbnails so 6K wallpapers don't get decoded at full size in the grid.
enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func load(_ url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
