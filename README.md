# Wallflow — still & live wallpapers for macOS

A native SwiftUI app for macOS 14 Sonoma and later, on Apple Silicon or Intel.

## Features
- **Huge 4K catalog, one search box.** Searches several free sources at once and blends the results into one endlessly scrolling grid:
  | Source | Content | Key |
  |---|---|---|
  | Wallhaven | 1M+ community wallpapers, a huge 4K/5K/8K collection (safe-for-work only) | not needed |
  | Bing Wallpaper of the Day | a new hand-picked 4K photo every day | not needed |
  | Unsplash | professional photos, originals usually 4K–8K | free |
  | Pexels | photos **and** 4K videos (live) | free |
  | Pixabay | HD/4K videos and animations (live) | free |
- **Filters:** minimum resolution (Full HD+, 1440p+, **4K+** by default, 5K+), sort (Popular, Latest, Random), colour swatches and 20 one-click topics.
- **Browse by source** in the sidebar, or all at once.
- **Live previews:** live wallpapers start playing when you hover over them, in Discover and in your Library.
- **Favourites:** click the heart on any wallpaper to save it in Full resolution and add it to Favourites.
- **Live wallpapers** play behind your desktop icons on every display and every Space, on a seamless, silent loop. You can set the speed (0.25×–2×), choose Fill or Fit, and dim the video (0–70%).
- **Auto-rotate:** change the wallpaper every 5 minutes up to once a day. Pick from your Library, your Favourites, or **new 4K wallpapers from the internet** for any search term. "Next Wallpaper" (⌘N) is also in the menu bar.
- **A different wallpaper on each display.**
- **Battery friendly:** playback pauses when a full-screen app covers the desktop, when displays sleep, when the Mac is locked, and optionally on battery power.
- **Lock screen:** the live wallpaper's first frame is shown on the lock screen and login window. There's also an *experimental* option that plays the video itself on the lock screen (see below).
- **Clean desktop mode:** hide desktop icons with one switch.
- **Library:** import your own images and videos, see how much space wallpapers use, and show the folder in Finder.
- **Menu bar icon**, Launch at Login and a Hide Dock icon option.

## Build & install
Requires Xcode 15 or later, or the Command Line Tools (`xcode-select --install`).
```bash
cd Wallflow
./scripts/build-app.sh
cp -R build/Wallflow.app /Applications/
open /Applications/Wallflow.app
```
To make a DMG installer instead, run `./scripts/make-dmg.sh`. It creates `build/Wallflow.dmg`.
If the code is on GitHub, the included workflow (`.github/workflows/build-dmg.yml`) builds the DMG on a Mac runner on every push to `main`. Download it from the run's **Artifacts**.

If you'd rather work in Xcode, open `Package.swift` and press Run. Launch at Login only works from the built `.app`.

The first time you open the app, macOS may block it because it isn't notarized. Right-click Wallflow.app and choose **Open**.

## First run
1. Still wallpapers work straight away through Wallhaven.
2. For **live wallpapers**, open **Settings (⌘,) › Sources** and paste a free key from Pexels and/or Pixabay. More keys mean a bigger catalog.
3. Turn on **Launch at login** so your live wallpaper comes back after a restart.

## About the lock screen (please read)
macOS has **no public API** that lets third-party apps play video on the lock screen. While your Mac is locked, apps can't draw anything there. The only wallpapers that move on the lock screen are Apple's own **Aerial** wallpapers.

Wallflow's experimental option (right-click a live wallpaper in Library › *Use on Lock Screen*):
1. Converts your video to HEVC.
2. Puts it in place of one Aerial video you've downloaded, in `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/`, after backing up the original. This needs your admin password.
3. Restarts the wallpaper service. With that Aerial selected in System Settings › Wallpaper, your video plays on the lock screen.

Caveats: this depends on how macOS works internally, which Apple can change. A macOS update may restore the original video. Use **Restore Original** in the same sheet to undo it. If the Aerial list stays empty, give Wallflow *Full Disk Access* in System Settings › Privacy & Security.

## Why not "everything on the internet"?
Most wallpaper sites ban scraping, and many images found online are copyrighted. Wallflow only uses official APIs whose content is licensed for this kind of use. Together they hold millions of images and hundreds of thousands of videos. To add a source, create a new `WallpaperProvider` in `Sources/Wallflow/Providers/` and add it to `Providers.all`.

## Project layout
```
Sources/Wallflow/
  WallflowApp.swift           app entry, menu bar extra, app delegate
  Core/Models.swift           Wallpaper / LocalWallpaper / Prefs
  Core/Catalog.swift          parallel multi-source search + paging
  Core/Library.swift          downloads, imports, poster frames
  Core/WallpaperEngine.swift  static wallpaper + desktop-level video windows
  Core/PlayerView.swift       seamless looping AVPlayer view
  Core/LockScreenAerial.swift experimental animated lock screen
  Providers/                  Wallhaven, Unsplash, Pexels, Pixabay
  Views/                      SwiftUI screens
```
