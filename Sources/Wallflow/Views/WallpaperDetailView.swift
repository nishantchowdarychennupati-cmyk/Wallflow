import SwiftUI

struct WallpaperDetailView: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var library: Library
    @EnvironmentObject var engine: WallpaperEngine
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Color.black
                if wallpaper.kind == .live {
                    LoopingVideoView(url: wallpaper.previewURL)
                } else {
                    AsyncImage(url: wallpaper.previewURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { AsyncImage(url: wallpaper.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { ProgressView() } }
                    }
                }
                FavoriteButton(wallpaper: wallpaper).padding(10)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.caption ?? wallpaper.author.map { "by \($0)" } ?? wallpaper.source)
                        .font(.headline).lineLimit(2)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let page = wallpaper.pageURL { Link("View on \(wallpaper.source)", destination: page) }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { run(nil, apply: false) }.disabled(working)
                if NSScreen.screens.count > 1 {
                    Menu("Set on Display") {
                        ForEach(NSScreen.screens, id: \.wallflowKey) { screen in
                            Button(screen.localizedName) { run(screen, apply: true) }
                        }
                    }
                    .fixedSize()
                    .disabled(working)
                }
                Button("Set as Wallpaper") { run(nil, apply: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(height: 18)
        }
        .padding(20)
        .frame(width: 900)
    }

    private var subtitle: String {
        var parts: [String] = []
        if wallpaper.kind == .live { parts.append("Live") }
        parts.append(wallpaper.resolutionLabel)
        parts.append(wallpaper.source)
        if wallpaper.caption != nil, let author = wallpaper.author { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    private func run(_ screen: NSScreen?, apply: Bool) {
        working = true
        status = wallpaper.kind == .live ? "Downloading video…" : "Downloading full resolution…"
        Task {
            defer { working = false }
            do {
                let item = try await library.download(wallpaper)
                if apply {
                    try engine.apply(item, to: screen)
                    status = wallpaper.kind == .live
                        ? "Live wallpaper is playing. Its first frame is shown on the lock screen."
                        : "Wallpaper set\(screen.map { " on \($0.localizedName)" } ?? " on all displays")."
                } else {
                    status = "Saved to your Library."
                }
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
