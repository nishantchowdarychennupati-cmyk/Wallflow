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
            ZStack {
                Color.black
                if wallpaper.kind == .live {
                    LoopingVideoView(url: wallpaper.previewURL)
                } else {
                    AsyncImage(url: wallpaper.previewURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { AsyncImage(url: wallpaper.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { ProgressView() } }
                    }
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.author.map { "by \($0)" } ?? wallpaper.source).font(.headline)
                    Text("\(wallpaper.kind == .live ? "Live · " : "")\(wallpaper.resolutionLabel) · \(wallpaper.source)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let page = wallpaper.pageURL { Link("View on \(wallpaper.source)", destination: page) }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save to Library") { run(apply: false) }.disabled(working)
                Button("Set as Wallpaper") { run(apply: true) }
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
        .frame(width: 860)
    }

    private func run(apply: Bool) {
        working = true
        status = wallpaper.kind == .live ? "Downloading video…" : "Downloading full resolution…"
        Task {
            defer { working = false }
            do {
                let item = try await library.download(wallpaper)
                if apply {
                    try engine.apply(item)
                    status = wallpaper.kind == .live
                        ? "Live wallpaper is playing. Its first frame is shown on the lock screen."
                        : "Wallpaper set on all displays."
                } else {
                    status = "Saved to your Library."
                }
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
