# Awesome Player - macOS Video Player

## Project Overview
A full-featured macOS video player combining Dolby Vision playback with AirPlay streaming, Chromecast casting, DLNA, and VLC-quality codec support. Inspired by Movist Pro's polished UI and VLC's codec breadth. Built with AppKit + AVFoundation + libvlc + FFmpeg.

## Architecture

### Dual-Engine Playback
- **AVPlayer**: For native MP4/MOV with H.264/HEVC — gets Dolby Vision, HDR10, HLG, AirPlay, and PiP
- **libvlc (VLC engine)**: For MKV, AVI, WebM, and any codec VLC supports — instant playback, no remuxing
- FFmpeg's `FFmpegBridge` is used for media probing, codec identification, track enumeration, embedded subtitle extraction, and as a fallback remuxer
- Both engines share a common control surface: SubtitleManager, ABLoopController, NowPlayingController, ResumeManager, PlaylistManager, OSDView

### Directory Structure
```
Awesome Player/
├── App/            # AppDelegate, URLOpenCoordinator (Open URL… / yt-dlp flow),
│                   # main.swift, Info.plist, AppIcon, Localizable.xcstrings (11 locales)
├── Player/         # AVPlayerEngine, VLCPlayerEngine (+AudioEqualizerPreset), ABLoopController,
│                   # ChapterNavigation (pure helpers, testable),
│                   # NowPlayingController, ResumeManager, OpenSubtitlesService (REST + Keychain)
├── Audio/          # AudioPassthrough, AudioPassthroughManager
├── Casting/        # CastingManager, ChromecastManager (Cast V2 facade), CastV2Connection
│                   # (protobuf framing + TLS socket), CastingHTTPClient (shared SOAP helper),
│                   # DLNAManager, CastingHTTPServer, AirPlayCastManager
├── Media/          # MediaInfo, SubtitleParser/Manager, PlaylistManager
├── FFmpeg/         # FFmpegBridge (Obj-C prober/remuxer/subtitle extractor), bridging header
├── UI/
│   ├── Window/     # PlayerWindow (borderless), PlayerWindowController, TitleBarView (badges)
│   ├── Player/     # PlayerViewController, VideoView, SubtitleOverlayView, WelcomeView,
│   │               # PlaylistPanelView, VideoEQPanelController, MediaInspectorController,
│   │               # ConvertStreamWindowController (+SystemUsageSampler), ScreenshotSaver,
│   │               # OpenSubtitlesSearchWindow
│   ├── Controls/   # ControlBarView, SeekSliderView, VolumeSliderView, PlaybackButtons,
│   │               # SpeedButton, CastButton
│   ├── OSD/        # OSDView (on-screen display messages)
│   ├── Menu/       # MenuManager (top-level + remaining smaller delegates),
│   │   └── Delegates/  # AirPlayMenuDelegate, ChromecastMenuDelegate, TrackMenuDelegate
│   └── Preferences/# PreferencesWindowController (9-tab, live language switch, LanguagePicker);
│                   # `BasePrefsView` consolidates the coder-init boilerplate so subclasses
│                   # just override `buildContent(_:)`
└── Utilities/      # Extensions (L() helper, LanguageManager, .languageDidChange notif),
                    # Defaults (~60 preference keys), KeyBindingManager, UpdateChecker,
                    # Logging (dlog/wlog façade — see "Logging" pitfall below)
Vendor/
├── ffmpeg/         # Bundled FFmpeg headers + dylibs
├── libvlc/         # Bundled libvlc headers, dylibs, plugins, libvlc_compat.h
└── yt-dlp/         # Bundled yt-dlp macOS binary + Python 3.14 runtime (_internal/)

# NOTE: Vendor/VLCKit (~1.6 GB) was the Objective-C wrapper around libvlc.
# We don't use it — every Swift file calls libvlc's C API directly (lower
# overhead, finer control). Deleted from the repo to shrink clone size.
```

### Build & Run
- macOS 14.0+ target, Xcode (Swift 5 + Obj-C)
- **Fully self-contained** — all dependencies bundled in `Vendor/`
- Build phase script auto-copies FFmpeg dylibs, libvlc dylibs, VLC plugins, and app icon
- User script sandboxing is disabled (`ENABLE_USER_SCRIPT_SANDBOXING = NO`) so build scripts can copy vendor binaries
- Just clone, open in Xcode, and Cmd+R

#### Local development (Debug build via Xcode)

The fast iteration loop. Build artifacts land in Xcode's DerivedData:

```bash
git clone https://github.com/zhaomin1995/awesome_player.git
cd awesome_player
open "Awesome Player.xcodeproj"
# Cmd+R in Xcode to build and run
```

After build, the `.app` is at:

```
~/Library/Developer/Xcode/DerivedData/Awesome_Player-<hash>/Build/Products/Debug/Awesome Player.app
```

This is *only* useful while developing. The path is deep, the binary is unoptimized + larger, and a fresh `pod`/clean wipes it.

#### Release build (for installing / distribution)

A Release configuration build is what you want when you're "done iterating" and want a stable copy in `/Applications`:

```bash
cd awesome_player
xcodebuild -project "Awesome Player.xcodeproj" \
           -scheme "Awesome Player" \
           -configuration Release \
           clean build
```

Result:

```
~/Library/Developer/Xcode/DerivedData/Awesome_Player-<hash>/Build/Products/Release/Awesome Player.app
```

Differences from Debug:
- Swift compiler optimizations (`-O`) — meaningfully smaller `.dylib`, slightly faster runtime
- No debug symbols in the main binary
- ~245 MB bundle vs ~250 MB Debug (most of the bulk is bundled libvlc plugins + yt-dlp runtime, which don't change)

#### Install to /Applications

```bash
# Locate the Release build
RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData/Awesome_Player-*/Build/Products/Release/ -name "Awesome Player.app" -maxdepth 1 -type d | head -1)

# Copy to /Applications (uses ditto so Mac metadata + symlinks survive)
sudo ditto "$RELEASE_APP" "/Applications/Awesome Player.app"
```

After install, double-clicking the app from `/Applications`, Launchpad, or Spotlight all work normally. First launch will show a "developer cannot be verified" warning (ad-hoc code signing) — right-click → **Open** → **Open** to bypass once.

#### Packaging for distribution (GitHub Release)

GitHub's regular tree has a 100 MB per-file limit; our zipped `.app` is ~100 MB and uncompressed is ~245 MB. So **do not `git add` the binary** — use GitHub Releases instead (2 GB per asset, bound to a tag).

```bash
# 1. Build Release
xcodebuild -project "Awesome Player.xcodeproj" -scheme "Awesome Player" -configuration Release clean build

# 2. Zip the .app preserving Mac metadata (ditto, NOT regular `zip`,
#    so resource forks and the bundle structure survive)
RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData/Awesome_Player-*/Build/Products/Release/ -name "Awesome Player.app" -maxdepth 1 -type d | head -1)
cd "$(dirname "$RELEASE_APP")"
ditto -c -k --keepParent "Awesome Player.app" /tmp/Awesome-Player-<version>.zip

# 3. Create the GitHub release with the zip attached
cd /path/to/awesome_player
gh release create v<version> /tmp/Awesome-Player-<version>.zip \
    --title "Awesome Player <version>" \
    --notes "..."
```

The first release was `v1.0` at https://github.com/zhaomin1995/awesome_player/releases/tag/v1.0 — use that release notes body as a template for future versions. Users download the zip, unzip, drag to `/Applications`, right-click → Open the first time to bypass ad-hoc signing warning.

**Why `ditto` and not `zip`:** macOS app bundles contain symlinks (Frameworks → Versions/A, etc.) and resource forks that regular `zip` mangles, producing a `.app` that crashes on launch with `dyld` errors. `ditto -c -k --keepParent` is Apple's officially-blessed tool for archiving `.app` bundles.

**Why ad-hoc signing**: the project uses `Sign to Run Locally` (no paid Apple Developer account). The binary works fine for personal/distribution use but triggers Gatekeeper warnings on first open. For a "no warning at all" experience the project would need an Apple Developer ID certificate ($99/year), `codesign --sign "Developer ID Application: ..."`, and notarization via `xcrun notarytool submit`.

### Key Technical Decisions
- AVPlayer for native formats preserves Dolby Vision and AirPlay
- libvlc for non-native formats gives VLC-identical playback quality
- Singleton VLC instance reused across file opens for fast startup
- libvlc_compat.h expanded to 90+ API declarations (track switching, EQ, audio delay, video adjust, deinterlace, crop, snapshot, subtitle SPU)
- FFmpegBridge wraps FFmpeg C APIs via Obj-C bridging header
- FFmpegBridge.videoCodecNameForFile() for codec badge display on non-native formats
- FFmpegBridge.extractSubtitleTrack() for embedded text subtitle extraction to SRT string
- FFmpegBridge.audioTracksForFile() and subtitleTracksForFile() for Media Inspector track enumeration
- UserDefaults-based Open Recent (custom RecentDocumentsMenuDelegate) because NSDocumentController requires document architecture
- MPRemoteCommandCenter for Now Playing / media keys (works on macOS 10.12.2+)
- NowPlayingController handles play/pause/toggle, skip forward/backward, next/previous track, and scrub position
- ResumeManager with VLC-style smart thresholds (3min duration, 5-95% position, 1min absolute, 1min remaining)
- TrackMenuDelegate dynamically queries active engine (AVPlayer or VLC) for tracks on menu open
- ASS style section parsing (V4+ Styles) produces NSAttributedString with font/color/bold/italic
- ASS color format (&HAABBGGRR) correctly parsed to NSColor with BGR byte order
- Chromecast uses Cast V2 protocol (protobuf over TLS, port 8009) with friendly name extraction from Bonjour TXT record "fn" key
- Audio passthrough detects AC3/E-AC3 capable devices via CoreAudio transport type inspection
- AudioDeviceMenuDelegate filters out virtual and aggregate audio devices using kAudioDevicePropertyTransportType
- All preference controls bound to UserDefaults via Cocoa Bindings
- Menu checkmarks track state (EQ preset, speed, aspect ratio, deinterlace mode, crop, subtitle position, etc.)
- Defaults enum has 90+ keys organized into 9 categories matching the 9 preference tabs
- VideoEQPanelController is a floating NSPanel that adjusts VLC video_adjust parameters in real-time
- MediaInspectorController is a floating NSPanel that probes the current file via FFmpegBridge
- yt-dlp is bundled in `Vendor/yt-dlp/` as a self-contained distribution (macOS universal binary + Python 3.14 runtime in `_internal/`)
- yt-dlp resolution for non-direct-media URLs: checks bundled binary first, then system paths (/opt/homebrew/bin, /usr/local/bin, /usr/bin)
- YouTube URL flow: `yt-dlp -j` fetches format metadata → resolution picker dialog → `yt-dlp --get-url -f FORMAT_ID` gets stream URLs
- For video-only high-res formats, VLC plays video with `:input-slave=AUDIO_URL` for separate audio stream
- `libvlc_media_new_location()` used for network URLs (vs `libvlc_media_new_path()` for local files)
- HTTP(S) URLs without file extensions (e.g., googlevideo.com `/videoplayback`) route to AVPlayer via `isNativeAVPlayerFormat`
- Process pipe reads use separate threads to avoid deadlock when yt-dlp writes large output
- i18n via Xcode 15 single-file `Localizable.xcstrings` catalog at `App/`. 11 locales: en (source) + zh-Hans / zh-Hant / yue (Cantonese) / ja / ko / es / fr / de / pt-BR / ru. All user-facing strings wrapped in `L("…")` helper from `Extensions.swift`
- `LanguageManager.shared` (in `Extensions.swift`) owns the active resource bundle and exposes `setLanguage(_:)` for runtime switching. `L()` routes through it instead of calling `NSLocalizedString` directly
- In-app language picker in General preferences uses `LanguagePicker` action handler — flips the menu bar + Preferences window + future dialogs **without relaunching**. Writes `AppleLanguages` UserDefaults key too so the choice persists across launches and affects system dialogs at next launch
- `EditMenuDelegate` strips the three items AppKit auto-injects into any menu containing `cut:/copy:/paste:` (AutoFill submenu, Start Dictation, Emoji & Symbols) — none make sense for a video player's URL/timecode dialog text fields
- AudioEqualizerPreset is a struct in `VLCPlayerEngine.swift` holding name + preamp + 10 ISO band amplifications. 23 Movist-style presets. EQ is built via `libvlc_audio_equalizer_new` + `libvlc_audio_equalizer_set_amp_at_index` (NOT libvlc's built-in `_new_from_preset` which only has 18 generic names)
- Subtitle styling: 16 HTML/CSS named colors with swatch images in menus, outline thickness via NSAttributedString `strokeWidth` (negative = fill + stroke), background color/opacity via NSAttributedString `backgroundColor` with alpha. KVO observers on UserDefaults so changes apply live to currently-displayed subtitle
- Playback Speed inline slider in Playback menu via `NSMenuItem.view` set to `PlaybackSpeedSliderView`. Log2 scale so 1.0× sits dead center between 0.25× and 4×
- Subtitle Background Opacity inline slider via `SubtitleOpacitySliderView`, same NSMenuItem.view pattern
- `PreferencesWindowController.TabDef` splits stable English `id` (used as NSTabViewItem + NSToolbarItem identifier) from localized `label` (shown to user). Toolbar identifiers MUST stay stable across locales or selection state breaks
- `ConvertStreamWindowController` in `UI/Player/` — VLC's File → Convert/Stream… equivalent. Uses libvlc sout pipeline (`:sout=#transcode{...}:standard{access=file,...}`). 12 profiles matching VLC's built-in set. Reuses `VLCPlayerEngine.sharedInstance` (libvlc supports multiple concurrent media players on one instance). Stream output not implemented
- `SystemUsageSampler` (bottom of `ConvertStreamWindowController.swift`) reports per-process CPU via `task_threads()` + `thread_info(THREAD_BASIC_INFO)` and system GPU via IORegistry `IOAccelerator` services reading `PerformanceStatistics["Device Utilization %"]`. Updated on the existing 500ms progress timer during conversion

## Development Guidelines

### Code Quality
- Keep good comment coverage — explain WHY, not WHAT
- Update this CLAUDE.md when architecture changes
- Run `xcodebuild` after every change to verify compilation
- Test with both MP4 (AVPlayer path) and MKV (VLC path) files

### Common Pitfalls
- FFmpeg + libvlc dylibs + yt-dlp distribution must be in app bundle at runtime (build phase handles this)
- yt-dlp's `_internal/` directory must be alongside the binary (set `currentDirectoryURL` when launching)
- `@main` on AppDelegate doesn't work without MainMenu.nib — use explicit `main.swift`
- libvlc headers are 3.x compatible (`libvlc_compat.h`) — don't use 4.x headers
- VLC plugin path must be set via `VLC_PLUGIN_PATH` env var before `libvlc_new()`
- `CFBundleIconFile` in Info.plist must match the .icns filename (no extension)
- VLC instance is a singleton (`sharedVLCInstance`) — don't call libvlc_release on it during normal playback; only in deinit
- `isPaused` checks AVPlayer rate (rate == 0) on the AVPlayer path; VLC path uses its own `isPlaying` flag
- `setVideoWindowSize` checks both `playerEngine?.videoSize` and `vlcEngine?.videoSize` for active engine
- `playbackStatusObservation` (KVO) must be nilled before stopping the player engine to avoid observing deallocated items
- yt-dlp `--no-playlist` flag is required to prevent resolving entire playlists (which hangs)
- The PyInstaller-built `yt-dlp_macos` single binary has `semctl` issues on macOS Tahoe; use the zip distribution instead
- Subtitle preferences (font/size/color) are live-updated via KVO observers on UserDefaults
- Window drag-and-drop is registered on the DragDropView (which is the root view of PlayerViewController), not on PlayerWindow or individual subviews
- RecentDocumentsMenuDelegate manages its own UserDefaults key because NSDocumentController requires the document-based app architecture
- TrackMenuDelegate has three static instances (.audio, .video, .subtitle) — each wired to a different submenu
- Video adjustments (brightness/contrast/saturation/hue/gamma) require enabling `libvlc_adjust_Enable` before setting float values
- Audio delay is in microseconds in libvlc but exposed as seconds in VLCPlayerEngine API
- Subtitle delay step is in seconds; audio delay step is in milliseconds (converted to seconds before applying)
- Chromecast menu extracts IPv4 address from resolved Bonjour addresses to avoid mDNS hostname resolution issues
- Edit menu (Cut/Copy/Paste/Select All) is required for text fields in NSAlert dialogs to accept keyboard shortcuts
- Window size is forced to 0.7x screen after showing to override macOS state restoration (`NSQuitAlwaysKeepsWindows` set to false)
- `ENABLE_USER_SCRIPT_SANDBOXING` must be `NO` or build scripts can't access `Vendor/` directory
- Bundled FFmpeg dylibs must use `@rpath` for inter-library deps, not absolute paths. If a freshly built/downloaded dylib has its install ID as `@rpath/...` but references siblings via an absolute build-machine path (visible in `otool -L`), the app will crash at launch with `dyld: Library not loaded` on any other machine. Patch with `install_name_tool -change /abs/path/libfoo.X.dylib @rpath/libfoo.X.Y.Z.dylib <dylib>` for each bad dep, then `codesign --force --sign - <dylib>` to restore the ad-hoc signature. The build script only copies fully-versioned files (e.g. `libavcodec.61.19.101.dylib`), so the `@rpath` target must be the fully-versioned name, not the major-only soname
- Xcode does NOT emit an `en.lproj/Localizable.strings` for the catalog's source language (`en` in our case). Trying to load `Bundle.main.path(forResource: "en", ofType: "lproj")` returns nil. `L()` must short-circuit and return the key directly when the active language is English — the keys ARE the English strings. Falling through to Bundle.main is wrong because…
- …`Bundle.main.preferredLocalizations` is frozen at app launch (computed from `AppleLanguages` at first lookup). It does NOT re-evaluate after a runtime `AppleLanguages` mutation. Anything that reads `NSLocalizedString` directly against Bundle.main will return launch-time-language strings forever — even after the user changes language in our picker. Always go through `LanguageManager.shared.bundle` instead
- CJK Forward/Backward direction translations are easy to invert (向前 = forward, 向後/向后 = backward). We caught a 5s seek shipping with the directions swapped via an LLM reviewer pre-ship. ALWAYS QA new translations with a native reviewer agent for any string mentioning direction, time, or sequence
- AppKit auto-injects three items into any menu it detects as the "Edit menu" (i.e. any menu with `cut:`/`copy:`/`paste:` items): AutoFill submenu, Start Dictation, Emoji & Symbols. They appear AFTER our `setupMainMenu()` runs, so we can't just not add them. To suppress, attach an `NSMenuDelegate` (we use `EditMenuDelegate`) that strips items by selector name (`orderFrontCharacterPalette:`, `startDictation:`) on `menuNeedsUpdate` / `menuWillOpen`. AutoFill's parent has nil action — match by localized title substring across all supported locales
- libvlc's `file-caching` default is **1000ms**. This was the root cause of the 1-second seek lag both we and VLC.app exhibited vs Movist Pro (which uses raw FFmpeg without libvlc's input-buffer layer). Set `:file-caching=100` as a media option — confirmed default value via `vlc-master/src/libvlc-module.c`
- libvlc `:input-fast-seek` media option snaps seeks to nearest keyframe instead of decoding forward to exact-frame target. Trade ~1s seek accuracy for sub-100ms response. Use it for parity with AVPlayer keyframe seeks
- AVPlayer's `automaticallyWaitsToMinimizeStalling` defaults to **true**. For local file playback this adds 100-300ms of perceived seek lag while AVPlayer refills its stall-protection buffer. Set it to `false` in `AVPlayerEngine.open()`. (Behavior was never observable in VLC.app or Movist Pro because they don't go through AVPlayer at all.)
- `AVPlayer.seek(to:toleranceBefore:toleranceAfter:)` automatically cancels any pending seek when a new one arrives. The "wait for current seek to finish, then start the pending one" coalescing pattern is harmful — on slider drags it doubles perceived latency because the next seek doesn't start until the previous one VISUALLY settles. Just call `playerItem?.cancelPendingSeeks()` and fire-and-forget the new seek
- Seek tolerance per call site: positive infinity (`.positiveInfinity`) for interactive seeks (slider scrub, arrow keys); 0.1s precise for programmatic exact-timestamp seeks (chapter nav, jump-to-time, resume from saved position)
- `AVPlayerLayer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), …]` prevents implicit CoreAnimation animations on those properties. Without this, the layer animates its bounds in parallel with `NSWindow.toggleFullScreen` — AVPlayer's render pipeline gets confused by the moving target and the video stalls for ~1-2s during the fullscreen transition. See `VideoView.setPlayer(_:)`
- The MKV file-open `FFmpegBridge.probeFile()` call for Dolby Vision detection must run on a background queue (`.userInitiated`), NOT the main thread. `avformat_find_stream_info` reads packets and can block for 100-300ms on a 4K file. `PlayerViewController.openFile` runs this async + uses a `currentFileURL == url` guard to drop the result if the user opened a different file mid-probe
- `THREAD_BASIC_INFO_COUNT` macro is NOT bridged to Swift. To call `thread_info()` with the basic-info flavor, compute the count manually: `mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)`
- IOKit's `IOAccelerator` services expose `PerformanceStatistics["Device Utilization %"]` — fully public IOKit API for reading GPU utilization on both Intel and Apple Silicon Macs. This is what Activity Monitor's GPU History uses. Walk via `IOServiceMatching("IOAccelerator")` + `IOIteratorNext` and read with `IORegistryEntryCreateCFProperties`
- Adding a new Swift file when not using Xcode requires manual edits to `project.pbxproj` at four spots: PBXBuildFile entry, PBXFileReference entry, group children list, and PBXSourcesBuildPhase / PBXResourcesBuildPhase files list. UUIDs in our project follow `A100XX` (build) and `F100XX` (file ref) pattern — pick unused IDs (e.g. `A10100`+) and reuse them in all four spots
- macOS auto-adds Emoji & Symbols via `orderFrontCharacterPalette:` selector and Start Dictation via `startDictation:` selector. These are public AppKit selectors — match by name for robust cross-locale stripping
- Floating panel controllers (`MediaInspectorController`, `VideoEQPanelController`) bake L() values at init time into NSTextField labels and have no live-refresh logic. On `.languageDidChange`, AppDelegate must nil them so the next open builds fresh views with new-locale strings. `PreferencesWindowController` is the exception — it observes the notification itself and rebuilds its tabs in place
- **Logging** — never use raw `print()` in production code. Use `dlog(.category, msg)` for debug-only verbose chatter (compiles to no-op in Release) and `wlog(.category, msg)` for genuinely-anomalous events (always emitted via `os_log` to Console.app). Earlier builds dumped device names, codec ids, and file paths to the unified log unfiltered. See `Utilities/Logging.swift`. The `castLog` in ChromecastManager is the one historical exception — it's already wrapped in `#if DEBUG`
- **Hot-path UserDefaults** — read in handlers fired per-event (keyDown, scrollWheel, time observer) must be cached to a stored property and refreshed via `UserDefaults.didChangeNotification`. See `PlayerViewController.refreshCachedPreferences()` for the pattern. Re-reading from UserDefaults inside a tight event loop both wastes cycles and can return a value mid-mutation
- **Thumbnail cache** — `SeekSliderView.thumbnailCache` is an `NSCache` with `totalCostLimit` (bytes), NOT a `[Int: NSImage]` with a hard-count ceiling. The old dict-based cache wiped itself wholesale at 150 entries, defeating caching on long films. Cost passed when inserting is `width * height * 4` (RGBA bytes)
- **Subtitle lookup** — `SubtitleManager.subtitle(at:)` does (a) probe currentIndex + neighbours (O(1) for monotonic playback) then (b) binary-search by `startTime` (O(log n)). Never reintroduce a linear scan — ASS files routinely have 5k+ cues and this fires 4×/s
- **Orphaned Defaults** — Preferences toggles that don't have a reader anywhere in the player should be deleted, NOT silently registered. A toggle that lies about doing something is worse than no toggle. If you add a new pref to `Defaults.swift`, also wire a reader (or don't add the UI row). Run `grep -rn "Defaults.<key>"` to confirm every key has at least one non-Prefs/non-Defaults reader
- **OpenSubtitles credentials** — API key + password live in macOS Keychain (generic-password, `service: com.awesomeplayer.opensubs`). Don't add a UserDefaults binding for them in the Preferences pane — the field uses `addKeychainFieldRow` which routes through `OpenSubtitlesService.setAPIKey` / `setCredentials`. Username is the one exception (UserDefaults — not sensitive, and the Keychain item needs the account string to look up the password)
- **ATS** — `NSAllowsArbitraryLoads` is OFF. Control-plane traffic (UpdateChecker, OpenSubtitlesService) must be HTTPS. AVPlayer can use cleartext for user-pasted media URLs because `NSAllowsArbitraryLoadsInMedia` is ON. Cast HTTP serve on the LAN works via `NSAllowsLocalNetworking`. Do NOT re-enable the global toggle — allowlist specific hosts via `NSExceptionDomains` instead
- **Hardened Runtime** — `ENABLE_HARDENED_RUNTIME = YES` is on; `com.apple.security.cs.disable-library-validation` is in the entitlements so adhoc-signed bundled libvlc plugins/dylibs still load. The proper future fix is `Scripts/sign-vendors.sh` codesigning every dylib with the app's identity, then dropping the entitlement
- **DV remux race** — `openFile` nils `playbackStatusObservation` BEFORE swapping engines, and the inner remux callback guards on `self.currentFileURL == url` so a stale probe completion can't clobber the new engine. The KVO closure captures `[weak engine]` for the same reason. Don't relax these guards — without them, opening a second file mid-probe leaks the prior engine and may double-trigger remux
- **DV temp .mp4 cleanup** — `PlayerViewController` tracks `dvRemuxOutputURL` and deletes the prior one on each `openFile`; `purgeOrphanedDVRemuxFiles` runs at viewDidLoad to sweep up files left behind by a previous crashed run. Naming convention is `<UUID>_full.mp4` in `temporaryDirectory` — match the suffix exactly
- **Cast source URL** — Chromecast/AirPlay handlers must read `vc.playbackSourceURL`, NOT `vc.currentFileURL` or `currentItem.asset as? AVURLAsset`. For DV files the engine is decoding the remuxed `.mp4`, but the source URL is still the original `.mkv` the receiver can't decode
- **Chapter navigation** — use `ChapterNavigation.nextChapterIndex` / `previousChapterIndex`, NOT inline `firstIndex(where:)` against `currentTime ± tolerance`. The old tolerance approach silently skipped chapters less than 1-2s apart. The helper uses the "containing chapter" definition (chapter whose [start, nextStart) range covers the time) and is unit-tested
- **i18n parity discipline** — any new `L("...")` call requires a corresponding key in `App/Localizable.xcstrings` with all 10 non-English translations. Run `Scripts/check-i18n.py` or `grep -rho 'L("[^"]\+")' "Awesome Player/" | sort -u` and diff against the catalog to catch regressions. Otherwise non-English users see English in the new dialogs. The Python script `/tmp/update_xcstrings.py` (in the prior hardening session) shows the JSON shape for bulk insert
- **`Defaults` keys must register a default value** in `Defaults.registerDefaults()` even when the consuming code already has a fallback (e.g. `customShortcuts` with `Data()`). Audit with `comm -23 <(declared) <(registered)` — every declared key should have a registered value
- **Bundle version source of truth** is pbxproj's `MARKETING_VERSION` (CFBundleShortVersionString) + `CURRENT_PROJECT_VERSION` (CFBundleVersion). Info.plist uses `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` placeholders — don't hardcode literal strings there, the two will drift silently
- **`UserDefaults.synchronize()`** — deprecated since macOS 10.12, no-op since 10.15. Don't add new calls; the framework auto-flushes on suspend/terminate
- **SeekSliderView thumbnail jobs** — when `currentAsset` changes, `cancelAllCGImageGeneration()` MUST run before `imageGenerator = nil` and before `thumbnailCache.removeAllObjects()`. Otherwise a job submitted against the old asset can complete and write into the new asset's NSCache slot, showing a stale thumb for one tooltip cycle
- **Logging** — never use raw `print()` in production code. `dlog(.category, msg)` is a no-op in Release; `wlog(.category, msg)` always emits via `os_log` for genuinely-anomalous events. `castLog` is just `dlog(.cast, message)` now — earlier versions wrote to `/tmp/chromecast_debug.log`, which leaked stream URLs and wasn't picked up by Console.app
- **OpenSubtitlesService is async/await** — all four network methods (`search`, `download`, `ensureLoggedIn`, `requestDownloadLink`, `downloadFile`) return `async throws`. Callers use `Task { try await OpenSubtitlesService.search(...) }` and hop to `MainActor.run` for UI updates. Don't add new completion-handler wrappers; UpdateChecker uses the same pattern
- **Casting refactor** — `ChromecastManager` (572 → ~360 lines) is now the discovery + media-control facade. `CastV2Connection.swift` owns the wire protocol: `CastV2Message` (protobuf encoder) + `NWConnectionWrapper` (TLS socket via CFStream — NWConnection/URLSessionStreamTask both fail against Chromecast's self-signed cert). `CastingHTTPClient.sendAVTransportAction` dedupes the SOAP-over-HTTP POST that both DLNAManager and AirPlayCastManager need
- **`BasePrefsView`** — preference panes inherit from `BasePrefsView` and override `buildContent(_ stack:)` instead of `init(frame:)`. This eliminates 9 identical `required init?(coder:) { fatalError() }` boilerplate sites. `InputPrefsView` doesn't use the base because it also conforms to NSTableView delegate protocols and keeps init-time table setup co-located with its properties
- **Floating panels refresh on language change** — `MediaInspectorController` + `VideoEQPanelController` each observe `.languageDidChange` and rebuild their labels in place. `ConvertStreamWindowController` does the same via a `refreshLocalizedText` method that re-sets section box / button titles. Earlier code only refreshed on next open, leaving visible windows stale. Same pattern: hold weak refs to the views, observe the notification, re-set titles
- **ATS hardening — `NSAllowsArbitraryLoads` is OFF.** Control-plane traffic (UpdateChecker, OpenSubtitlesService) is HTTPS-enforced. AVPlayer can use cleartext for user-pasted media URLs because `NSAllowsArbitraryLoadsInMedia` is ON. Cast HTTP serve works via `NSAllowsLocalNetworking`. Don't re-enable the global toggle — allowlist specific hosts via `NSExceptionDomains` instead
- **Test target** — wired in pbxproj (T00002, build phases S00002/FB0002/R00002, configs BC0030/BC0031). Shared scheme at `xcshareddata/xcschemes/Awesome Player.xcscheme` so `xcodebuild test` finds it. Two known issues:
  1. On **Xcode 26 + macOS 26 the local `xcodebuild test` CLI fails to launch the test bundle** with `LaunchServices error -54` ("sandbox profile of this process is missing (allow lsopen)"). This is a system-level xcodebuild sandboxing issue, NOT a project problem — tests run fine from Xcode UI (Cmd+U) and on CI's macos-15 runner. Workaround for local CLI: run from Xcode.
  2. `ENABLE_HARDENED_RUNTIME = NO` is set on the test target so the test bundle can inject into the (hardened) host app — Xcode's xctest injection requires the test bundle itself to be unrestricted
- **Architecture pin: `ARCHS = arm64` in Release** — Vendor/ffmpeg + Vendor/libvlc dylibs are arm64-only. Xcode 26's "Standard Architectures" began including x86_64 again, silently breaking Release builds with `symbol(s) not found for architecture x86_64`. Don't drop the pin unless the vendor binaries gain a fat slice

### Casting Dolby Vision (currently unsupported — see findings)

DV casting is intentionally disabled. When the user clicks AirPlay on a DV
file, the app shows an OSD "Casting Dolby Vision isn't supported. Play
locally instead." Local DV playback still works correctly via the existing
DV-detect → remux to MP4 with `dvh1` tag → AVPlayer hardware DV decoder path.

This section is a knowledge dump from a long investigation. **Don't rebuild
without reading this first**; we spent significant time discovering that
none of the obvious transports actually work for DV→non-DV TVs end-to-end.

**The fundamental problem.** Non-DV TVs (Samsung, most non-LG-OLED sets)
can decode HEVC HDR10 natively, but not DV. So the file has to be
transcoded DV → HDR10 first. The transcode itself is solved (libplacebo's
`apply_dolbyvision=true` filter applies the RPU's IPT→BT.2020 reshape per
frame). The unsolved part is *how to ship the result to the TV*.

**What was attempted, transport by transport (Samsung S90F as the
reference receiver — others may differ):**

| Transport | What happens | Verdict |
|---|---|---|
| **AVKit AirPlay** (AVRoutePickerView/AVPlayer) | Session opens, TV shows "Connected to MacBook" banner, media never flows | Silent fail. Samsung's licensed AirPlay 2 SDK handshake doesn't engage with macOS AVKit reliably. Works fine for Apple TV. |
| **libvlc chromecast renderer** (Cast V2) | VLC.app pushes successfully but its sout chain re-encodes HEVC HDR10 → H.264 SDR — wrong colors on TV. Fails entirely from our process despite identical libvlc + plugins + permissions; root cause never identified. | Cast V2 receivers re-encode regardless. Always lossy. |
| **DLNA push, plain MP4 + faststart** | TV decodes HEVC HDR10 natively, correct colors. **But faststart requires a complete file** (final pass moves moov to start), so this is offline-only — full transcode finishes before push (~17 min for a 47-min file on M4). | Works for content, fails for UX. |
| **DLNA push, fragmented MP4** (`+frag_keyframe+empty_moov+default_base_moof`) | TV connected, parsed headers, then displayed **"File format not supported"** on screen. | Rejected. Samsung's DLNA player doesn't accept fMP4. |
| **DLNA push, MPEG-TS** (HEVC HDR10 in TS) | TV did HEAD only, then refused to issue GET. | Rejected on HEAD inspection. Samsung's TS decoder is reserved for broadcast/USB, not DLNA. |
| **DLNA push, HLS** (.m3u8 + .ts segments) | Same as TS — TV did HEAD on the playlist, didn't follow up. | Rejected. HLS over DLNA isn't supported by Samsung's MediaRenderer. |

**Empirical conclusion.** Samsung's DLNA path accepts *only* plain MP4
with `moov` at the file start. That format inherently requires a finished
transcode. Live streaming to this TV via DLNA is not possible.

**What was removed when we shelved this:**
- `Awesome Player/Player/HDRTranscoder.swift` — Subprocess wrapper that
  spawned ffmpeg with libplacebo and parsed `-progress` output. Reusable
  for any DV/HDR transcode need.
- `Vendor/ffmpeg-cli/` — Self-contained ffmpeg sidecar (~34 MB): binary
  built from FFmpeg 7.1 with `--enable-libplacebo --enable-videotoolbox`
  + libplacebo + Vulkan loader + MoltenVK + lcms2 + shaderc + ICD JSON.
  All dylibs `@rpath`-patched; binary rpath `@executable_path/../lib`.
- `CastingHTTPServer.isLiveMode` + `CastingManager.castLive` — Live-mode
  HTTP plumbing (advertised growing-file sizes, waited for bytes past
  EOF). Never proved useful since Samsung rejected the live formats.
- The DV-cast flow in `PlayerViewController` (transcode → DLNA picker →
  push pipeline).

**What was kept** (real bug fixes / generally useful):
- All `DLNAManager` fixes (BSD-socket SSDP, `descriptionURL` from SSDP
  LOCATION, walking `<service>` blocks for AVTransport, async-race in
  `loadMedia`). These are bug fixes that benefit any DLNA usage.
- DLNA headers in `CastingHTTPServer` (`transferMode.dlna.org`,
  `contentFeatures.dlna.org`).
- `CastButton` dual-mode (AVKit picker / custom NSButton). Useful any
  time we need a custom AirPlay handler.
- `AVPlayerEngine.allowsExternalPlayback` configurability.
- Local DV playback path (remux to MP4 + `dvh1` tag + AVPlayer DV decoder).

**Revival path** (if new tech or firmware enables this):

1. Bring back `HDRTranscoder.swift` from git history (commit before this
   was shelved). It's general infrastructure, no DV-only assumptions.
2. Rebuild `Vendor/ffmpeg-cli/`: build FFmpeg 7.1 with
   `--enable-libplacebo --enable-videotoolbox` against
   `brew install libplacebo` (which pulls Vulkan loader + MoltenVK +
   shaderc + lcms2). Patch install names with `install_name_tool` to
   `@rpath`. Re-sign each binary with `codesign --force --sign -`. The
   ICD JSON must live at `<bundle>/etc/vulkan/icd.d/MoltenVK_icd.json`
   so its relative `../../../lib/libMoltenVK.dylib` path resolves; set
   `VK_ICD_FILENAMES` env var before spawning ffmpeg.
3. Restore `CastingHTTPServer.isLiveMode` and `CastingManager.castLive`
   if doing live (but verify the receiver actually accepts the chosen
   live format — the existing growing-file logic is correct in principle
   but Samsung specifically rejected every live format we tried).
4. Wire the DV-detect branch in `PlayerViewController.controlBarAirPlayRequested`
   to launch the transcode + push flow instead of the "not supported" OSD.

**Things that might change the landscape:**
- Apple opens up an AirPlay 2 video sender API that handles Samsung's
  handshake quirks. (Unlikely.)
- Samsung firmware update accepts fMP4 or HLS via DLNA. (Possible —
  worth re-testing periodically.)
- An open-source AirPlay 2 video sender library matures on macOS.
  (Worth watching the `pyatv` / `airpyle` ecosystem.)
- We accept the offline transcode wait and ship it with a background
  pre-transcode UX (start ffmpeg when DV file opens, finish before user
  clicks AirPlay). Doable today without new tech; just deprioritized.

### DLNA discovery/control quirks (DLNAManager)

- SSDP M-SEARCH MUST use BSD sockets (`socket` + `sendto` + `recvfrom`), not `NWConnection`. NWConnection's UDP "connection" is bound to the destination endpoint (the multicast group 239.255.255.250 in this case) and silently drops the unicast responses that come back from the device's own IP. This was the actual reason DLNAManager appeared "discovered nothing" against any device.
- `fetchDeviceDescription` must use the `LOCATION:` URL from the SSDP advertisement, not a hardcoded path. Samsung Smart TVs use `/dmr` (e.g. `http://10.0.0.126:9197/dmr`); other vendors use `/xml/device_description.xml`, `/description.xml`, etc. `CastDevice` carries `descriptionURL` populated from the SSDP response.
- When parsing the description XML, walk `<service>` blocks looking for one whose `<serviceType>` contains `AVTransport`. Naively grabbing the first `<controlURL>` picks RenderingControl on Samsung (declared first), which doesn't understand SetAVTransportURI.
- `DLNAManager.loadMedia(url:on:)` auto-chains `fetchDeviceDescription` if `controlURL` is nil — `connect()`'s URL fetch is async, so callers that call `connect()` then immediately `loadMedia()` would otherwise hit a nil-controlURL silent return.
- `CastingHTTPServer` must emit `transferMode.dlna.org: Streaming` and a non-empty `contentFeatures.dlna.org` header on the file response, or Samsung MediaRenderer rejects/ignores the URL. The `DLNA.ORG_OP=01` flag opts into both seek-by-time and seek-by-byte.

### AirPlay button click routing (CastButton)

- `AVRoutePickerView` doesn't expose its picker open as an action target; it captures `mouseDown` via private tracking-area machinery that bypasses sibling overlay views (an `NSView` placed on top of the picker doesn't reliably win hit testing — its `mouseDown` never fires even with `acceptsFirstMouse` and custom `hitTest`). To intercept clicks for the DV/libvlc path, `CastButton` switches between two implementations: `AVRoutePickerView` for the native AVKit path, and a plain `NSButton` with the `airplayvideo` SF Symbol for the DV path. `setMode(.customHandler)` tears down the picker view entirely.
- `AVPlayerEngine.allowsExternalPlayback` is now a configurable property (default `true`). DV files set it to `false` so AVKit doesn't auto-engage external playback when an AirPlay route is system-active (which would blank the local video and show a "Playing on TV" placeholder that never actually streams).

### Misc gotchas hit during DV work

- A traced/stopped process (Xcode debugger attached) can't be terminated via `kill -9`. The `ps` `STAT` column shows `SX`. Users must quit Xcode or detach the debugger; shell-level kills do nothing.
- `dovi_tool -m 2/3 convert` only rewrites RPU metadata to claim Profile 8.1; it doesn't transcode the IPT-PQ base layer pixels to BT.2020-PQ. AVPlayer/AppleTV don't apply the RPU's color transform when they see a P8.1 file, so the relabeled file plays with the same wrong colors as the original P5. The only working approach is full pixel transcode via libplacebo, which does apply the RPU per-frame.

### Internationalization (i18n)

**Format.** Single-file Xcode 15+ string catalog at `Awesome Player/App/Localizable.xcstrings`. Source language is English. Keys are the English strings themselves (not abstract identifiers like `menu.playPause`) — `L("Play / Pause")` is the standard call site. Xcode compiles the catalog into `<locale>.lproj/Localizable.strings` for each non-source locale at build time.

**Supported locales (11):** `en` (source), `zh-Hans`, `zh-Hant`, `yue` (Cantonese), `ja`, `ko`, `es`, `fr`, `de`, `pt-BR`, `ru`. Listed in `Info.plist` under `CFBundleLocalizations` and in `project.pbxproj` under `knownRegions`.

**L() helper.** From `Utilities/Extensions.swift`:
```swift
func L(_ key: String, comment: String = "") -> String {
    if LanguageManager.shared.isEnglish { return key }
    return LanguageManager.shared.bundle.localizedString(forKey: key, value: key, table: nil)
}
```
The English short-circuit is essential — Xcode does NOT emit `en.lproj` for the source language, so a bundle lookup for "en" returns nil and the code would silently fall through to Bundle.main, which has its `preferredLocalizations` frozen at app launch.

**LanguageManager.** Singleton in `Extensions.swift`. Holds:
- `customBundle: Bundle?` — non-nil when user explicitly picked a non-English locale
- `effectiveLanguage: String` — the picked code, or `""` for System Default
- `systemDefaultLang: String` — snapshot of `Bundle.main.preferredLocalizations.first` at app launch (used for System Default mode's English detection, since Bundle.main is frozen)
- `isEnglish: Bool` — true if `effectiveLanguage == "en"` OR (System Default AND systemDefaultLang is English)
- `setLanguage(_ code: String?)` — swap customBundle + write AppleLanguages + post `.languageDidChange`

**Live language switch (no relaunch).** Flow when user picks a language in Preferences:
1. `LanguagePicker.languageChanged(_:)` calls `LanguageManager.shared.setLanguage(code)`
2. LanguageManager swaps `customBundle`, writes `AppleLanguages = [code]`, posts `.languageDidChange`
3. LanguagePicker rebuilds main menu: `NSApp.mainMenu = nil; MenuManager.setupMainMenu()`
4. `PreferencesWindowController.handleLanguageChange` (notification observer) rebuilds its tabs + toolbar in place via `rebuildTabs(selectedId:)`, preserving the currently-selected tab. Window stays open
5. `AppDelegate.languageDidChange` (notification observer) nils `inspectorController` + `videoEQController` — floating panels bake L() at init time and don't have refresh logic, so next-open builds fresh
6. Other UI is dynamic (filename in title bar, OSD messages, dialog text, time labels) or icon-based (control bar buttons) — picks up new language on next render with no extra work

**TabDef pattern.** `PreferencesWindowController.TabDef` separates `id` (stable English, never changes — used as NSTabViewItem + NSToolbarItem identifier) from `label` (localized via `L()`, shown to user). The toolbar identifier MUST stay stable across locales or toolbar selection state breaks on language switch. Same pattern would apply to any toolbar/tab UI in the future.

**Endonym picker.** `LanguagePicker.languages` lists each language by its own endonym (English, 简体中文, 廣東話, 日本語, Русский, …) rather than translating the language name with the rest of the UI. Essential for recovery — if a user accidentally picks Japanese, "日本語" is still visible in the picker so they can switch back. Translating would make the picker entry disappear in the wrong locale.

**Translation QA workflow.** When adding new keys or auditing existing ones:
1. Extract per-language `{key, value}` tables from the .xcstrings with a Python script
2. Spawn one Claude reviewer subagent per language with the table + locale-specific style guidance (Apple macOS conventions, common terminology, format-specifier preservation, proper noun list)
3. Each agent returns ONLY entries needing correction as JSON
4. Apply with validation (key exists, old value matches, format specifiers preserved), reject anything that doesn't pass
5. Real bug caught this way: 5s seek direction (Forward/Backward) was inverted in zh-Hans AND zh-Hant — 向后跳 was labeled "forward". Native reviewer agents both flagged it independently. Always have native reviewers verify direction/sequence words.

**Pitfalls specific to .xcstrings catalogs:**
- Format specifiers (`%@`, `%d`, `%.1f`, `%%`) must appear in the same positions in every translation. Apple's localization compiler will warn but not error; check Activity log on builds. Some languages reorder placeholders — use `%1$@`, `%2$@` positional form for those (we don't have any yet but be aware)
- Proper nouns (AirPlay, Chromecast, DLNA, Dolby Vision, HDR, MP4, MOV, FFmpeg, VLC, libvlc, yt-dlp, dB, Hz, Hip-Hop, R&B, Yadif, Bob, Blend) stay untranslated in EVERY locale. Don't let reviewers "translate" them
- EQ preset names (Bass Booster, Vocal Booster, etc.) translate to local equivalents — match Apple Music conventions per locale. R&B and Hip-Hop are loanwords in most locales; keep as English

### Convert/Stream Window

**Backend.** Uses libvlc's sout (stream output) chain. The transcode media option:
```
:sout=#transcode{vcodec=X,acodec=Y,ab=192,channels=2,samplerate=44100}:standard{access=file,mux=Z,dst=PATH}
```
Reuses `VLCPlayerEngine.sharedInstance` (libvlc supports multiple concurrent media players on one instance — creating a second instance would double the VLC plugin scan cost ~50ms). The conversion player is headless (we don't call `libvlc_media_player_set_nsobject`).

**12 profiles** in `ConvertStreamWindowController.profiles`, mirroring VLC.app's built-in set (H.264+MP3/MP4, VP80+Vorbis/WebM, Theora+Vorbis/OGG, Theora+FLAC/OGG, MPEG-2+MPGA/TS, WMV+WMA/ASF, DIV3+MP3/ASF, audio-only Vorbis/MP3/MP3-in-MP4/FLAC).

**Progress.** Polled every 500ms via `libvlc_media_player_get_position` (0.0–1.0). ETA computed from elapsed wall time and position. Status label and progress bar update on the same timer.

**CPU/GPU display.** `SystemUsageSampler` at bottom of `ConvertStreamWindowController.swift`:
- `currentProcessCPUPercent()` — walks our process's threads via `task_threads()` + `thread_info(THREAD_BASIC_INFO)` and sums `cpu_usage / TH_USAGE_SCALE * 100`. 100% = one core saturated; multi-threaded workloads exceed 100%. Matches `top`'s %CPU column
- `currentGPUPercent()` — walks IORegistry for `IOAccelerator` services, reads `PerformanceStatistics["Device Utilization %"]`. Works on Intel + Apple Silicon. Returns max across services (handles multi-GPU). Fully public IOKit API

**Typical observed values during H.264+MP3 conversion on M-series:**
- CPU: 30–60% (x264 software encoder is the bottleneck)
- GPU: 10–20% (VideoToolbox doing the decode side; encode is software)

If you ever want a hardware-encoded profile, the libvlc option is `vcodec=h264_videotoolbox` — different sout chain. Would shift load from CPU to GPU.

**Stream output (network sink) not implemented.** The Stream button shows a "not implemented" alert. Adding it properly needs another dialog for protocol/host/port — out of scope for the initial cut.

**Window layout pitfall.** `statusLabel` and `usageLabel` need explicit bottom anchors to `contentView.bottomAnchor` with padding (`-20pt`). Without bottom constraints they end up flush with the window border (no padding). `goButton` bottom anchor at `-40pt` to leave room for the two text rows beneath the progress bar.

### Performance Tuning History

The numbers cited here were measured on M4 Mac mini against VLC.app 3.0.23 and Movist Pro 2.15.4 with 4K HEVC test files. Important for understanding why some seemingly-trivial settings exist.

**Discovered seek-lag root cause: libvlc `file-caching` default = 1000ms.** Both we and VLC.app showed ~1 second of seek lag on the libvlc engine path — confirmed identical via side-by-side testing. Movist Pro had instant seeks because it uses raw FFmpeg without libvlc's input-buffer layer. Reading `vlc-master/src/libvlc-module.c` confirmed: `add_integer( "file-caching", 1000, …)`. Override with `:file-caching=100` in media options. We also set `:network-caching=300` (default 1000) for streaming.

**AVPlayer seek lag eliminated by `automaticallyWaitsToMinimizeStalling = false`.** Default true makes AVPlayer pause after seeks to refill stall-protection buffer — 100-300ms of perceived lag for local files where buffering protection is wasted work. The previous "smoothSeek with completion-handler coalescing" pattern was actively harmful: on drag, mouseUp's seek waited for mouseDown's seek to VISUALLY settle before starting, doubling perceived lag. Removed the coalescing entirely — AVPlayer already cancels pending seeks when a new `seek(to:)` arrives.

**Per-call-site seek tolerance.** `AVPlayerEngine.seek(by:)` and `seekToFraction(_:)` use `.positiveInfinity` (keyframe seek, ~10ms latency). `seekTo(time:)` uses `CMTimeMakeWithSeconds(0.1, …)` (precise, ~100-500ms). Chapter nav and jump-to-time go through `seekTo(time:)` so they're precise; everything else is keyframe.

**Optimistic time-label update.** `ControlBarView`'s seek slider closure updates the time label IMMEDIATELY to the new fractional position, instead of waiting up to 250ms for the next AVPlayer time-observer fire. Visually the time label and slider thumb now jump in sync — feels instant even on slow large files.

**Fullscreen stutter fix.** `AVPlayerLayer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "sublayers": NSNull(), "contents": NSNull()]` in `VideoView.setPlayer(_:)`. Without it, the layer animates its bounds in parallel with `NSWindow.toggleFullScreen` and AVPlayer stalls for the ~1-2s cross-animation. Also wraps the sublayer-frame update in `VideoView.layout()` in a `CATransaction { setDisableActions(true) }` block as belt-and-suspenders.

**MKV file-open latency: async DV probe.** `PlayerViewController.openFile` previously called `FFmpegBridge.probeFile()` synchronously on main thread for non-native files, blocking the UI for 100-300ms on 4K files (`avformat_find_stream_info` reads packets to detect codecs). Now wraps in `DispatchQueue.global(qos: .userInitiated).async` with a `currentFileURL == url` guard for race protection. Engine selection extracted into per-engine helpers (`startAVPlayerEngine`, `startDolbyVisionRemuxFlow`, `startVLCEngine`).

**Architecture trade-off vs Movist Pro (for context).** Movist Pro uses pure FFmpeg + VideoToolbox + Metal — no libvlc, no AVPlayer for non-native. Its seek and frame timing are slightly better than ours BECAUSE it owns the entire pipeline. Our dual-engine (AVPlayer + libvlc) approach is the pragmatic choice for codec breadth at low engineering cost (~600 lines of libvlc wrapper vs ~3000 lines to build a Movist-style pipeline). After all the tuning above, we're within ~50-100ms of Movist Pro on every metric we measured, which is good enough.

### Git Repository
- Repo: https://github.com/zhaomin1995/awesome_player
- Branch: main
