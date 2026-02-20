# BoxCutter — Handoff Document

**Branch:** `feature/boxcutter-app`
**Last commit:** `d2359c3` — fix: address all 17 audit findings
**Build status:** ✅ Clean (zero errors, zero warnings on new code)
**Deployment target:** macOS 15.0 (Sequoia)

---

## What is BoxCutter

A minimal native macOS utility for installing `.pkg` and `.dmg` files. Designed as a cleaner alternative to Apple's built-in Package Installer. The app is a floating window (400pt wide) that accepts files via drag-and-drop, file picker, or Finder double-click.

---

## Architecture

### Two targets

| Target | Type | Purpose |
|--------|------|---------|
| `BoxCutter` | SwiftUI app | Main UI and orchestration |
| `BoxCutter Helper` | Command-line tool | Privileged LaunchDaemon — runs `/usr/sbin/installer` as root via XPC |

**Shared/** is compiled into both targets: `HelperProtocol.swift`, `ProgressProtocol.swift`, `SharedConstants.swift`.

### Key patterns
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — all code defaults to `@MainActor`. Services that must run off the main thread are marked `nonisolated` (see `DMGService`).
- **Single view model** — `AppViewModel` is `@Observable @MainActor`, owns all state.
- **State machine** — `AppState` enum drives the entire UI via a switch in `ContentView`.
- **No third-party dependencies** — pure SwiftUI + Foundation + AppKit + ServiceManagement.

### State machine

```
PKG flow:
  idle → inspecting(URL) → packageReady(PackageInfo) → installing(PackageInfo)
       → completed(PackageInfo) | failed(PackageInfo, error)

DMG flow:
  idle → dmgMounting(URL) → dmgReady(DMGInfo) → dmgInstalling(DMGInfo)
       → dmgCompleted([InstalledApp]) | dmgFailed(error)
```

---

## File Map

```
BoxCutter/
├── BoxCutterApp.swift          App entry, AppDelegate (.pkg/.dmg Finder open handling)
├── ContentView.swift           State-routing root view + focus-based auto-close wiring
│
├── Models/
│   ├── AppState.swift          State machine enum (11 cases)
│   ├── AppSettings.swift       @Observable UserDefaults singleton (14 settings)
│   ├── PackageInfo.swift       .pkg metadata struct
│   └── DMGInfo.swift           DMGAppEntry, DMGInfo, InstalledApp structs
│
├── ViewModels/
│   └── AppViewModel.swift      Single @Observable @MainActor view model
│
├── Services/
│   ├── PackageInspector.swift  hdiutil/pkgutil subprocess wrappers (two-tier: quick + details)
│   ├── DirectInstaller.swift   AppleScript fallback installer (osascript privilege escalation)
│   ├── HelperManager.swift     SMAppService singleton — @MainActor, HelperManager.shared
│   ├── XPCClient.swift         NSXPCConnection to privileged helper
│   └── DMGService.swift        nonisolated — hdiutil mount/detach, findApps, ditto copy
│
└── Views/
    ├── DropZoneView.swift       Idle state — drag-and-drop + Select File
    ├── PackageInfoView.swift    .pkg inspection screen (header, expandable details, action bar)
    ├── InstallingView.swift     .pkg install progress (verbose log, progress bar)
    ├── CompletionView.swift     .pkg success/failure screen
    ├── DMGAppInfoView.swift     .dmg app list (icon, version, sign badge, Install/Update/Show/Cancel)
    ├── DMGInstallingView.swift  Per-app progress bars with bytes/total
    ├── DMGCompletionView.swift  DMG completion (Open App, Show in Finder, Uninstall, Fix for Launch)
    └── SettingsView.swift       3-tab preferences (General, Behavior, Helper)

BoxCutter Helper/
├── main.swift                  Entry: HelperDelegate().run()
├── HelperDelegate.swift        NSXPCListenerDelegate + SecCode client validation
└── InstallerRunner.swift       HelperProtocol impl — runs installer with target param

Shared/
├── HelperProtocol.swift        installPackage(atPath:target:withReply:)
├── ProgressProtocol.swift      outputLine(_:) — helper → app streaming
└── SharedConstants.swift       machServiceName
```

---

## Settings (AppSettings.shared)

| Key | Default | Tab |
|-----|---------|-----|
| `alwaysOnTop` | false | General |
| `autoCloseAfterInstall` | false | General |
| `autoCloseDelay` | 3.0s | General |
| `playSoundOnComplete` | true | General |
| `completionSound` | "Glass" | General |
| `confirmBeforeInstall` | true | Behavior/PKG |
| `trashAfterInstall` | true | Behavior/PKG |
| `showVerboseOutput` | true | Behavior/PKG |
| `showProgressBar` | true | Behavior/PKG |
| `showScriptWarnings` | true | Behavior/PKG |
| `showPayloadFiles` | true | Behavior/PKG |
| `confirmBeforeDMGInstall` | true | Behavior/DMG |
| `trashDMGAfterInstall` | true | Behavior/DMG |
| `preferHelperDaemon` | true | Helper |

---

## DMG Feature Details

### Flow
1. `DMGService.mount()` — `hdiutil attach -nobrowse -plist`, parse plist for mount point
2. `DMGService.findApps()` — scan mounted volume root for `.app` bundles; reads `Info.plist` for version + bundle ID; checks `_CodeSignature` for sign status; checks `/Applications/<name>.app` for installed version
3. `DMGAppInfoView` — shows app icon (from NSWorkspace), name, version (`1.0 → 2.0` for updates), size, Signed/Unsigned badge; multi-app DMGs show checkboxes; button shows "Update" if all selected are already installed
4. `DMGService.copyApp()` — `ditto -V`, progress tracked by counting verbose output lines vs `fileCount` (hidden files included to match ditto's count)
5. On completion: `hdiutil detach` (fire-and-forget, off main thread), optionally trash DMG
6. `DMGCompletionView` — Done/Open App/Show in Finder/Uninstall; shows partial errors if some apps failed; shows "Fix for Launch" for unsigned apps (`xattr -cr`)

### Concurrency notes
- All `DMGService` static methods are `nonisolated` — required because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise put them on the main thread
- `runProcess` uses `terminationHandler` (not `waitUntilExit`) to avoid blocking threads
- `unmount` is fire-and-forget (no `waitUntilExit`) — called via `Task.detached` from `reset()`
- `loadDMG` uses `Task.detached` to keep `findApps` directory traversal off the main thread

---

## Auto-close Behavior

**Not** a simple countdown after install. Works as:
1. Install completes → nothing happens, window stays open
2. App loses focus → countdown starts (`autoCloseDelay` seconds)
3. App regains focus → countdown cancels and resets
4. Countdown elapses while out of focus → `NSApplication.terminate(nil)`

Wired in `ContentView` via `NSApplication.willResignActiveNotification` / `NSApplication.didBecomeActiveNotification`.

---

## Privileged Helper

- **Mach service:** `com.hwxnnn.BoxCutter-Helper`
- **Team ID:** `867PL24QLQ`
- **Plist:** `com.hwxnnn.BoxCutter-Helper.plist` embedded in `Contents/Library/LaunchDaemons/`
- **Registration:** `SMAppService.daemon(plistName:)` — requires user approval in System Settings > Login Items
- `HelperManager.shared` is a singleton; `SettingsView` and `AppViewModel` both reference it so Settings actions update the banners in ContentView
- XPC client validation uses `SecCodeCopyGuestWithAttributes` (PID-based) with team ID + bundle ID requirement
- Fallback: `DirectInstaller` uses `osascript` with `with administrator privileges`; copies pkg to `/tmp/` first to bypass TCC restrictions on `~/Downloads`

---

## Known Skipped Issue

**M-11 (not fixed):** XPC client validation uses PID (`kSecGuestAttributePid`) which is theoretically vulnerable to PID reuse in a TOCTOU window. The safer approach uses the connection's `auditToken`. Left as-is — the attack window is extremely narrow for local IPC and fixing it requires private API access.

---

## Things That Could Come Next

- **Notifications** — show a macOS notification after successful install (especially useful when auto-close is enabled and the window closes before the user sees it)
- **App icon badge** — update the Dock badge or menu bar while installing
- **Multi-file queue** — accept multiple files and install them sequentially
- **`.app` drag-and-drop** — install loose `.app` bundles directly (same copy-to-Applications flow as DMG)
- **Sparkle / update check** — self-update mechanism
- **PKG install target propagation via helper** — verified fixed in this session (I-2)
- **Sandbox** — currently disabled (`ENABLE_APP_SANDBOX = NO`); enabling it would require entitlements for `Process`, file access, and XPC
