import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            RotationSettings().tabItem { Label("Auto-Rotate", systemImage: "arrow.triangle.2.circlepath") }
            PlaybackSettings().tabItem { Label("Live Playback", systemImage: "play.rectangle") }
            SourcesSettings().tabItem { Label("Sources", systemImage: "globe") }
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var desktopIconsHidden = DesktopIcons.areHidden
    @State private var libraryBytes: Int64 = 0

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Wallflow at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Live wallpapers and auto-rotate need Wallflow running. Turn this on so they come back after a restart.")
                    .font(.caption).foregroundStyle(.secondary)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Hide Dock icon (use the menu bar icon)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, hide in
                        NSApp.setActivationPolicy(hide ? .accessory : .regular)
                    }
            }
            Section("Desktop") {
                Toggle("Hide desktop icons (clean wallpaper view)", isOn: $desktopIconsHidden)
                    .onChange(of: desktopIconsHidden) { _, hide in DesktopIcons.setHidden(hide) }
                Text("Your files stay where they are. Finder just stops drawing them on the desktop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                LabeledContent("Library size", value: ByteCountFormatter.string(fromByteCount: libraryBytes, countStyle: .file))
                HStack {
                    Button("Show Library Folder") { NSWorkspace.shared.open(Library.shared.folder) }
                    Button("Clear Thumbnail Cache") {
                        URLCache.shared.removeAllCachedResponses()
                        HTTP.session.configuration.urlCache?.removeAllCachedResponses()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { libraryBytes = Library.shared.diskUsage() }
    }
}

enum DesktopIcons {
    static var areHidden: Bool {
        UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool == false
    }

    static func setHidden(_ hidden: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "defaults write com.apple.finder CreateDesktop -bool \(hidden ? "false" : "true") && killall Finder"]
        try? task.run()
    }
}

// MARK: - Auto-rotate

private struct RotationSettings: View {
    @AppStorage("rotateMinutes") private var minutes = 0
    @AppStorage("rotateSource") private var source = "library"
    @AppStorage("rotateQuery") private var query = "nature"
    @AppStorage("rotateKind") private var kind = "any"
    @ObservedObject private var rotator = Rotator.shared

    private let intervals: [(Int, String)] = [
        (0, "Off"), (5, "Every 5 minutes"), (15, "Every 15 minutes"), (30, "Every 30 minutes"),
        (60, "Every hour"), (180, "Every 3 hours"), (720, "Every 12 hours"), (1440, "Every day"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Change wallpaper", selection: $minutes) {
                    ForEach(intervals, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Pick from", selection: $source) {
                    Text("My Library").tag("library")
                    Text("My Favorites").tag("favorites")
                    Text("The internet (new wallpapers)").tag("online")
                }
                if source == "online" {
                    TextField("Search term", text: $query, prompt: Text("e.g. mountains, space, minimal"))
                    Text("Wallflow downloads a random 4K wallpaper matching this search each time and adds it to your Library.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Type", selection: $kind) {
                    Text("Any").tag("any")
                    Text("Still only").tag("still")
                    Text("Live only").tag("live")
                }
            }
            Section {
                HStack {
                    Button("Next Wallpaper Now") { Task { await rotator.next() } }
                        .disabled(rotator.isWorking)
                    if rotator.isWorking { ProgressView().controlSize(.small) }
                }
                if let error = rotator.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Tip: “Next Wallpaper” is also in the menu bar (⌘N).").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Playback

private struct PlaybackSettings: View {
    @AppStorage("pauseOnBattery") private var pauseOnBattery = false
    @AppStorage("playbackRate") private var rate = 1.0
    @AppStorage("videoFill") private var fill = true
    @AppStorage("dimLevel") private var dim = 0.0

    var body: some View {
        Form {
            Section("Look") {
                Picker("Scaling", selection: $fill) {
                    Text("Fill screen").tag(true)
                    Text("Fit (letterbox)").tag(false)
                }
                .pickerStyle(.segmented)
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $rate, in: 0.25...2, step: 0.25)
                        Text(String(format: "%.2g×", rate)).monospacedDigit().frame(width: 40)
                    }
                }
                LabeledContent("Dim") {
                    HStack {
                        Slider(value: $dim, in: 0...0.7)
                        Text("\(Int(dim * 100))%").monospacedDigit().frame(width: 40)
                    }
                }
                Text("Dimming keeps bright videos easy on the eyes and makes desktop icons easier to read.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Battery") {
                Toggle("Pause live wallpaper on battery power", isOn: $pauseOnBattery)
                Text("Live wallpapers always pause when the desktop is fully covered, when displays sleep and when your Mac is locked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sources

private struct SourcesSettings: View {
    var body: some View {
        Form {
            Text("Wallflow searches these sources at the same time. Wallhaven and Bing work without a key. The others need a free API key, which takes about a minute to get.")
                .foregroundStyle(.secondary)
            ForEach(Providers.all.indices, id: \.self) { index in
                ProviderRow(provider: Providers.all[index])
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderRow: View {
    let provider: WallpaperProvider
    @AppStorage private var key: String
    @AppStorage private var enabled: Bool

    init(provider: WallpaperProvider) {
        self.provider = provider
        _key = AppStorage(wrappedValue: "", "apiKey.\(provider.name)")
        _enabled = AppStorage(wrappedValue: true, "enabled.\(provider.name)")
    }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(provider.name).font(.headline)
                        if provider.needsKey {
                            Text(provider.isConfigured ? "Key added" : "Needs key")
                                .font(.caption2.bold())
                                .foregroundStyle(provider.isConfigured ? .green : .orange)
                        }
                    }
                    Text(provider.blurb).font(.caption).foregroundStyle(.secondary)
                }
            }
            if provider.signupURL != nil || provider.needsKey {
                SecureField(provider.needsKey ? "API key (required)" : "API key (optional)", text: $key)
            }
            if let url = provider.signupURL {
                Link("Get a free \(provider.name) API key", destination: url).font(.caption)
            }
        }
    }
}
