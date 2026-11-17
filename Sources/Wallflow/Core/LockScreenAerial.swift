import AppKit
import AVFoundation

/// EXPERIMENTAL: animated lock screen.
///
/// macOS has no public API for third-party animated lock screens. The only wallpapers that animate
/// on the lock screen are Apple's own "Aerial" wallpapers (macOS 14 Sonoma and later). Their
/// downloaded videos live in a system folder. This swaps your video in place of one aerial
/// video (keeping a backup), so when that aerial is selected in System Settings › Wallpaper,
/// your video plays on the lock screen. Needs an admin password. macOS updates or
/// re-downloads may put Apple's original back.
struct AerialSlot: Identifiable, Hashable {
    let url: URL
    let modified: Date
    let sizeMB: Int
    var id: URL { url }
    var backupPath: String { url.path + ".wallflow-backup" }
    var isReplaced: Bool { FileManager.default.fileExists(atPath: backupPath) }
}

enum AerialError: LocalizedError {
    case folderMissing, exportFailed(String), script(String)
    var errorDescription: String? {
        switch self {
        case .folderMissing:
            return "No downloaded Aerial wallpapers found. Pick an Aerial in System Settings › Wallpaper first and let it download. If you already did, give Wallflow Full Disk Access in System Settings › Privacy & Security."
        case .exportFailed(let msg): return "Couldn't convert the video: \(msg)"
        case .script(let msg): return msg
        }
    }
}

enum LockScreenAerial {
    static let folder = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS")

    static func slots() throws -> [AerialSlot] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            throw AerialError.folderMissing
        }
        let slots = files.filter { $0.pathExtension == "mov" }.map { url -> AerialSlot in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return AerialSlot(url: url, modified: values?.contentModificationDate ?? .distantPast,
                              sizeMB: (values?.fileSize ?? 0) / 1_000_000)
        }.sorted { $0.modified > $1.modified }
        if slots.isEmpty { throw AerialError.folderMissing }
        return slots
    }

    static func thumbnail(for slot: AerialSlot) async -> NSImage? {
        // Prefer the backup (Apple's original) so the user can recognise which aerial it is.
        let source = slot.isReplaced ? URL(fileURLWithPath: slot.backupPath) : slot.url
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.maximumSize = CGSize(width: 320, height: 320)
        guard let result = try? await generator.image(at: CMTime(seconds: 2, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: result.image, size: .zero)
    }

    @MainActor
    static func install(video: URL, into slot: AerialSlot) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wallflow-aerial-\(UUID().uuidString).mov")
        try await transcodeToHEVC(video, to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = q(slot.url.path), backup = q(slot.backupPath)
        try runAsAdmin("""
        [ -f \(backup) ] || cp -p \(target) \(backup); \
        cp -f \(q(tmp.path)) \(target) && chmod 644 \(target); \
        killall WallpaperAgent 2>/dev/null; killall idleassetsd 2>/dev/null; true
        """)
    }

    @MainActor
    static func restore(_ slot: AerialSlot) throws {
        try runAsAdmin("""
        [ -f \(q(slot.backupPath)) ] && mv -f \(q(slot.backupPath)) \(q(slot.url.path)); \
        killall WallpaperAgent 2>/dev/null; killall idleassetsd 2>/dev/null; true
        """)
    }

    private static func transcodeToHEVC(_ input: URL, to output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
            ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AerialError.exportFailed("no export preset available")
        }
        session.outputURL = output
        session.outputFileType = .mov
        await session.export()
        if session.status != .completed {
            throw AerialError.exportFailed(session.error?.localizedDescription ?? "unknown error")
        }
    }

    /// Shell-quote a path.
    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @MainActor
    private static func runAsAdmin(_ shell: String) throws {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else {
            throw AerialError.script("Couldn't prepare the install script")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            throw AerialError.script(error[NSAppleScript.errorMessage] as? String ?? "Cancelled")
        }
    }
}
