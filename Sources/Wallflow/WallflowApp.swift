import AppKit
import SwiftUI

@main
struct WallflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var catalog = Catalog()
    @StateObject private var library = Library.shared
    @StateObject private var engine = WallpaperEngine.shared

    var body: some Scene {
        WindowGroup("Wallflow", id: "main") {
            ContentView()
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(engine)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 780)

        MenuBarExtra("Wallflow", systemImage: "photo.on.rectangle.angled") {
            MenuBarContent()
                .environmentObject(library)
                .environmentObject(engine)
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        URLCache.shared = URLCache(memoryCapacity: 128 << 20, diskCapacity: 1 << 30)
        if Prefs.hideDockIcon { NSApp.setActivationPolicy(.accessory) }
        Task { @MainActor in WallpaperEngine.shared.restore(from: Library.shared) }
    }

    // Keep running (and keep the live wallpaper playing) after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuBarContent: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var engine: WallpaperEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let id = engine.currentID, let item = library.item(id: id) {
            Text("Now: \(item.title)")
        }
        if engine.isLive {
            Button(engine.isPaused ? "Resume Live Wallpaper" : "Pause Live Wallpaper") { engine.togglePause() }
        }
        Button("Shuffle from Library") {
            if let pick = library.items.filter({ $0.id != engine.currentID }).randomElement() { try? engine.apply(pick) }
        }
        .disabled(library.items.count < 2)
        Menu("Shuffle by Type") {
            Button("Random Live Wallpaper") {
                if let pick = library.items.filter({ $0.kind == .live }).randomElement() { try? engine.apply(pick) }
            }
            Button("Random Still Wallpaper") {
                if let pick = library.items.filter({ $0.kind == .still }).randomElement() { try? engine.apply(pick) }
            }
        }
        Divider()
        Button("Open Wallflow…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Wallflow") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
