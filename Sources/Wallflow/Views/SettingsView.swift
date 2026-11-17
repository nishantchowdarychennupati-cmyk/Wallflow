import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SourcesSettings().tabItem { Label("Sources", systemImage: "globe") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 560)
        .padding(20)
    }
}

private struct SourcesSettings: View {
    var body: some View {
        Form {
            Text("Wallflow searches these free sources at the same time. Wallhaven works without a key. The others need a free API key.")
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
                    Text(provider.name).font(.headline)
                    Text(provider.supportedKinds.sorted { $0.rawValue > $1.rawValue }.map { $0 == .still ? "Still images" : "Live videos" }.joined(separator: " + "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            SecureField(provider.needsKey ? "API key (required)" : "API key (optional)", text: $key)
            if let url = provider.signupURL {
                Link("Get a free \(provider.name) API key", destination: url).font(.caption)
            }
        }
    }
}

private struct GeneralSettings: View {
    @AppStorage("pauseOnBattery") private var pauseOnBattery = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

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
                Text("Live wallpapers need Wallflow running. Turn this on so they come back after a restart.")
                    .font(.caption).foregroundStyle(.secondary)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Hide Dock icon (use the menu bar icon)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, hide in
                        NSApp.setActivationPolicy(hide ? .accessory : .regular)
                    }
            }
            Section("Live wallpapers") {
                Toggle("Pause live wallpaper on battery power", isOn: $pauseOnBattery)
                Text("Live wallpapers also pause when the desktop is fully covered, when displays sleep and when your Mac is locked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                Button("Show Library Folder in Finder") {
                    NSWorkspace.shared.open(Library.shared.folder)
                }
            }
        }
        .formStyle(.grouped)
    }
}
