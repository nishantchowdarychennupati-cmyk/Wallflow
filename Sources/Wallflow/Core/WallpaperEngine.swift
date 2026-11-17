import AppKit
import AVFoundation
import IOKit.ps

extension NSScreen {
    /// Stable identifier for a display.
    var wallflowKey: String {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName
    }
}

/// Applies wallpapers. Still images go through NSWorkspace; live wallpapers are played in a
/// borderless window at desktop level (below desktop icons) on each display and every Space.
/// Each display can have its own wallpaper; "*" is the default for all displays.
@MainActor
final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    @Published private(set) var assignments: [String: String]
    @Published private(set) var isLive = false
    @Published private(set) var isPaused = false

    var currentID: String? { assignments["*"] ?? assignments.values.first }
    func isCurrent(_ id: String) -> Bool { assignments.values.contains(id) }

    private var windows: [String: LiveScreen] = [:]
    private var userPaused = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var onBattery = false
    private var tokens: [NSObjectProtocol] = []
    private var powerTimer: Timer?

    private init() {
        assignments = UserDefaults.standard.dictionary(forKey: "wallpaperAssignments") as? [String: String] ?? [:]
        if assignments.isEmpty, let legacy = UserDefaults.standard.string(forKey: "currentWallpaperID") {
            assignments = ["*": legacy]
        }
        observeSystem()
    }

    /// Apply to every display (screen == nil) or a single display.
    func apply(_ item: LocalWallpaper, to screen: NSScreen? = nil) throws {
        if let screen { assignments[screen.wallflowKey] = item.id } else { assignments = ["*": item.id] }
        UserDefaults.standard.set(assignments, forKey: "wallpaperAssignments")
        try refresh()
    }

    /// Called at launch so live wallpapers survive app restarts and reboots (with Launch at Login).
    func restore() { try? refresh() }

    func togglePause() {
        userPaused.toggle()
        updatePlayback()
    }

    // MARK: - Internals

    private func refresh() throws {
        var firstError: Error?
        var liveKeys = Set<String>()
        for screen in NSScreen.screens {
            let key = screen.wallflowKey
            guard let id = assignments[key] ?? assignments["*"], let item = Library.shared.item(id: id) else { continue }
            do {
                switch item.kind {
                case .still:
                    try setDesktopPicture(item.fileURL, on: screen)
                case .live:
                    // The first frame becomes the system wallpaper, so the lock screen, login window and
                    // Mission Control match the live wallpaper.
                    if FileManager.default.fileExists(atPath: item.posterURL.path) {
                        try? setDesktopPicture(item.posterURL, on: screen)
                    }
                    liveKeys.insert(key)
                    if let existing = windows[key], existing.url == item.fileURL {
                        existing.place(on: screen)
                    } else {
                        windows[key]?.close()
                        windows[key] = LiveScreen(screen: screen, url: item.fileURL) { [weak self] in self?.updatePlayback() }
                    }
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        for (key, window) in windows where !liveKeys.contains(key) {
            window.close()
            windows[key] = nil
        }
        isLive = !windows.isEmpty
        windows.values.forEach { $0.applySettings() }
        updatePlayback()
        if let firstError { throw firstError }
    }

    private func setDesktopPicture(_ url: URL, on screen: NSScreen) throws {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ])
    }

    private func updatePlayback() {
        let paused = userPaused || screensAsleep || sessionInactive || (Prefs.pauseOnBattery && onBattery)
        isPaused = paused
        // Each screen also pauses itself when fully covered (e.g. a full-screen app) to save battery.
        windows.values.forEach { $0.sync(paused: paused) }
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
        on(.default, NSApplication.didChangeScreenParametersNotification) { try? $0.refresh() }
        on(.default, UserDefaults.didChangeNotification) { engine in
            engine.windows.values.forEach { $0.applySettings() }
            engine.updatePlayback()
        }

        checkPower()
        powerTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPower() }
        }
    }

    private func checkPower() {
        let source: String? = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?
        let battery = source == "Battery Power"
        if battery != onBattery { onBattery = battery; updatePlayback() }
    }
}

/// One desktop-level video window for one display.
@MainActor
private final class LiveScreen: NSObject {
    let url: URL
    private let window: NSWindow
    private let playerView: LoopingPlayerNSView
    private let onVisibilityChange: @MainActor () -> Void

    init(screen: NSScreen, url: URL, onVisibilityChange: @escaping @MainActor () -> Void) {
        self.url = url
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
        place(on: screen)
        window.orderFront(nil)
        applySettings()

        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }

    @objc private func occlusionChanged(_ note: Notification) { onVisibilityChange() }

    func place(on screen: NSScreen) { window.setFrame(screen.frame, display: true) }

    func applySettings() {
        playerView.configure(fill: Prefs.videoFill, rate: Prefs.playbackRate, dim: Prefs.dimLevel)
    }

    func sync(paused: Bool) {
        if paused || !window.occlusionState.contains(.visible) { playerView.pause() } else { playerView.play() }
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        playerView.stop()
        window.orderOut(nil)
        window.close()
    }
}
