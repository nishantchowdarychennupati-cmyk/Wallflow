import ImageIO
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var engine: WallpaperEngine
    @State private var filter: WallpaperKind?
    @State private var importing = false
    @State private var lockScreenItem: LocalWallpaper?
    @State private var error: String?

    private var visible: [LocalWallpaper] { library.items.filter { filter == nil || $0.kind == filter } }

    var body: some View {
        ScrollView {
            if library.items.isEmpty {
                ContentUnavailableView("Your library is empty",
                                       systemImage: "square.stack",
                                       description: Text("Save wallpapers from Discover, or import your own images and videos."))
                    .padding(.top, 80)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(visible) { item in
                    LocalCard(item: item, isCurrent: item.id == engine.currentID)
                        .onTapGesture(count: 2) { apply(item) }
                        .contextMenu {
                            Button("Set as Wallpaper") { apply(item) }
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
        .navigationTitle("Library")
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

    private func apply(_ item: LocalWallpaper) {
        do { try engine.apply(item) } catch { self.error = error.localizedDescription }
    }
}

struct LocalCard: View {
    let item: LocalWallpaper
    let isCurrent: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.secondary.opacity(0.15)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
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
