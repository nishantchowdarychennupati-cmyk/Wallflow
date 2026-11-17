import AppKit
import AVFoundation
import SwiftUI

/// A layer-hosting view that plays a video on a seamless, muted loop.
final class LoopingPlayerNSView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private let dimLayer = CALayer()
    private var looper: AVPlayerLooper?
    private(set) var url: URL?

    init(url: URL) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        dimLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.addSublayer(dimLayer)
        layer = playerLayer
        wantsLayer = true
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        setURL(url)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        dimLayer.frame = bounds
    }

    func setURL(_ newURL: URL) {
        guard newURL != url else { return }
        url = newURL
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: newURL))
        player.play()
    }

    /// Live-wallpaper display settings.
    func configure(fill: Bool, rate: Double, dim: Double) {
        playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        dimLayer.opacity = Float(min(max(dim, 0), 0.9))
        player.defaultRate = Float(rate)
        if player.rate != 0 { player.rate = Float(rate) }
    }

    func play() { if player.rate == 0 { player.play() } }
    func pause() { player.pause() }

    func stop() {
        player.pause()
        looper?.disableLooping()
        player.removeAllItems()
    }
}

struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> LoopingPlayerNSView { LoopingPlayerNSView(url: url) }
    func updateNSView(_ view: LoopingPlayerNSView, context: Context) { view.setURL(url) }
    static func dismantleNSView(_ view: LoopingPlayerNSView, coordinator: ()) { view.stop() }
}
