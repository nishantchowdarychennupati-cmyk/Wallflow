import AppKit
import AVFoundation
import IOKit.ps

/// Applies wallpapers. Still images go through NSWorkspace; live wallpapers are played in a
/// borderless window that sits at desktop level (below desktop icons) on every screen and Space.
@MainActor
final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    @Published private(set) var currentID: String? = UserDefaults.standard.string(forKey: "currentWallpaperID")
    @Published private(set) var isLive = false
    @Published private(set) var isPaused = false

    private var liveURL: URL?
    private var screens: [LiveScreen] = []
    private var userPaused = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var onBattery = false
    private var tokens: [NSObjectProtocol] = []
    private var powerTimer: Timer?

    private init() { observeSystem() }

    func apply(_ item: LocalWallpaper) throws {
        switch item.kind {
        case .still:
            stopLive()
            try setDesktopPicture(item.fileURL)
        case .live:
            // The first frame becomes the system wallpaper, so the lock screen, login window and
            // Mission Control match the live wallpaper.
            if FileManager.default.fileExists(atPath: item.posterURL.path) {
                try? setDesktopPicture(item.posterURL)
            }
            startLive(item.fileURL)
        }
        currentID = item.id
        UserDefaults.standard.set(item.id, forKey: "currentWallpaperID")
    }

    /// Called at launch so a live wallpaper survives app restarts and reboots (with Launch at Login).
    func restore(from library: Library) {
        guard let id = currentID, let item = library.item(id: id), item.kind == .live else { return }
        startLive(item.fileURL)
    }

    func togglePause() {
        userPaused.toggle()
        updatePlayback()
    }

    func stopLive() {
        liveURL = nil
        screens.forEach { $0.close() }
        screens = []
        isLive = false
    }

    // MARK: - Internals

    private func setDesktopPicture(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
    }

    private func startLive(_ url: URL) {
        liveURL = url
        rebuildWindows()
    }

    private func rebuildWindows() {
        screens.forEach { $0.close() }
        screens = []
        guard let url = liveURL else { isLive = false; return }
        screens = NSScreen.screens.map { screen in
            LiveScreen(screen: screen, url: url) { [weak self] in self?.updatePlayback() }
        }
        isLive = true
        updatePlayback()
    }

    private func updatePlayback() {
        let paused = userPaused || screensAsleep || sessionInactive || (Prefs.pauseOnBattery && onBattery)
        isPaused = paused
        // Each screen also pauses itself when fully covered (e.g. a full-screen app) to save battery.
        screens.forEach { $0.sync(paused: paused) }
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (WallpaperEngine) -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { body(self) } }
            })
        }
        on(ws, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true; $0.updatePlayback() }
        on(ws, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false; $0.updatePlayback() }
        on(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true; $0.updatePlayback() }
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false; $0.updatePlayback() }
        on(.default, NSApplication.didChangeScreenParametersNotification) { $0.rebuildWindows() }

        checkPower()
        powerTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPower() }
        }
    }

    private func checkPower() {
        let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?
        let battery = source == "Battery Power"
        if battery != onBattery { onBattery = battery; updatePlayback() }
    }
}

/// One desktop-level video window for one display.
@MainActor
private final class LiveScreen: NSObject {
    private let window: NSWindow
    private let playerView: LoopingPlayerNSView
    private let onVisibilityChange: @MainActor () -> Void
    private var paused = false

    init(screen: NSScreen, url: URL, onVisibilityChange: @escaping @MainActor () -> Void) {
        self.onVisibilityChange = onVisibilityChange
        playerView = LoopingPlayerNSView(url: url)
        window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = playerView
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)

        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }

    @objc private func occlusionChanged(_ note: Notification) { onVisibilityChange() }

    func sync(paused: Bool) {
        self.paused = paused
        if paused || !window.occlusionState.contains(.visible) { playerView.pause() } else { playerView.play() }
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        playerView.stop()
        window.orderOut(nil)
        window.close()
    }
}
