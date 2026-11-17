import SwiftUI

/// Experimental: play a live wallpaper on the lock screen by putting it in an Apple Aerial's place.
struct LockScreenSheet: View {
    let item: LocalWallpaper
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [AerialSlot] = []
    @State private var thumbs: [URL: NSImage] = [:]
    @State private var chosen: AerialSlot?
    @State private var status: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Wallpaper on the Lock Screen").font(.title2.bold())
            Text("""
            macOS only animates Apple's own Aerial wallpapers on the lock screen. Wallflow can put \
            this video in place of one Aerial's video so it plays on your lock screen too.
            """)
            .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open System Settings › Wallpaper and pick any Aerial (for example, under Landscape). Wait for it to download.")
                    Text("2. Click Refresh below and choose that same Aerial. The newest download is listed first.")
                    Text("3. Click Install and enter your Mac password. Lock your Mac (⌃⌘Q) to check it.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Text("Downloaded Aerials").font(.headline)
                Spacer()
                Button("Open Wallpaper Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
                }
                Button("Refresh") { load() }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(slots) { slot in
                        VStack(spacing: 4) {
                            ZStack {
                                Color.secondary.opacity(0.2)
                                if let img = thumbs[slot.url] { Image(nsImage: img).resizable().scaledToFill() }
                            }
                            .frame(width: 176, height: 99)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: chosen == slot ? 3 : 0))
                            Text(slot.isReplaced ? "Replaced by Wallflow" : slot.modified.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(slot.isReplaced ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        }
                        .onTapGesture { chosen = slot }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 130)

            HStack {
                if working { ProgressView().controlSize(.small) }
                if let status { Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore Original") { restore() }.disabled(chosen?.isReplaced != true || working)
                Button("Install") { install() }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen == nil || working)
            }
            Text("Experimental: this uses system files that aren't meant for apps to change. A macOS update may put Apple's original video back, and then you can just install again.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 720)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            slots = try LockScreenAerial.slots()
            chosen = chosen.flatMap { c in slots.first { $0.url == c.url } } ?? slots.first
            status = nil
            for slot in slots where thumbs[slot.url] == nil {
                Task { thumbs[slot.url] = await LockScreenAerial.thumbnail(for: slot) }
            }
        } catch {
            slots = []
            status = error.localizedDescription
        }
    }

    private func install() {
        guard let slot = chosen else { return }
        working = true
        status = "Converting video to HEVC (this can take a minute)…"
        Task {
            defer { working = false }
            do {
                try await LockScreenAerial.install(video: item.fileURL, into: slot)
                status = "Installed. Make sure that Aerial is selected in Wallpaper settings, then lock your Mac to see it."
                load()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard let slot = chosen else { return }
        do {
            try LockScreenAerial.restore(slot)
            status = "Apple's original Aerial was restored."
            load()
        } catch { status = error.localizedDescription }
    }
}
