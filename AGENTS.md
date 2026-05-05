> Agents: this file is your session-start reference for this repo. Keep it accurate. Update the affected section in the same commit when you change: dependencies, build/dev/test/lint/typecheck/format commands, top-level layout, required env vars, formatter/linter/tsconfig rules, entry points, or when you discover a non-obvious gotcha. Skip updates for routine bug fixes, new files following existing patterns, or in-file refactors. Keep additions terse and machine-readable. Delete sections that no longer apply. Replace `TODO(agent):` markers when you have ground truth. Do not rewrite sections you didn't touch.

## Stack

- Language: Swift 5, SwiftUI
- Platform: macOS 15.0+ (`MACOSX_DEPLOYMENT_TARGET = 15.0`; helper target uses `26.2`)
- No package manager, no third-party deps. Pure Apple SDKs (SwiftUI, AppKit, ServiceManagement, Security, XPC).
- App is **not sandboxed**. Do not claim otherwise without changing entitlements.

## Layout

```
BoxCutter/              main SwiftUI app target
  BoxCutterApp.swift    @main, window setup, open-file handling, launch cleanup
  ContentView.swift     top-level UI switch on AppState; helper status banners
  Models/               AppState, AppSettings, PackageInfo, DMGInfo
  Services/             PackageInspector, DirectInstaller, HelperManager, XPCClient, DMGService
  ViewModels/           AppViewModel — central @Observable @MainActor state machine
  Views/                DropZone, PackageInfo, Installing, Completion, DMG*, Settings
  Assets.xcassets/      app icon, accent color
BoxCutter Helper/       privileged launchd daemon target
  main.swift            creates HelperDelegate, runs RunLoop
  HelperDelegate.swift  XPC listener + client code-signing validation (security-critical)
  InstallerRunner.swift root-side `installer` runner with streamed output (security-critical)
  com.hwxnnn.BoxCutter-Helper.plist  embedded into Contents/Library/LaunchDaemons
Shared/                 compiled into both targets
  SharedConstants.swift Mach service name
  HelperProtocol.swift  app→helper XPC protocol
  ProgressProtocol.swift helper→app output streaming protocol
BoxCutter.xcodeproj/    Xcode project; preserve shared schemes
assets/                 README screenshots/icon (not shipped in app)
```

## Commands

List schemes/targets:
```sh
xcodebuild -list -project BoxCutter.xcodeproj
```

Debug build:
```sh
xcodebuild -quiet -project BoxCutter.xcodeproj -scheme BoxCutter -configuration Debug -destination 'platform=macOS' build
```

Release build (no signing — verifies compile only):
```sh
xcodebuild -quiet -project BoxCutter.xcodeproj -scheme BoxCutter -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Diff sanity:
```sh
git diff --check
```

No test target, no lint config, no formatter config. Use compile success as the verification baseline.

## Conventions

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Static funcs and free declarations are `@MainActor` by default. Mark long-running filesystem/process work `nonisolated` to keep it off the main actor.
- UI/state mutation lives behind `AppViewModel` (`@Observable @MainActor`).
- Process wrappers: prefer continuations + termination handlers over `waitUntilExit` on main thread.
- Do not capture non-`Sendable` objects (e.g. `FileManager`) into `@Sendable` closures (process termination/readability handlers).
- File naming: PascalCase Swift filenames matching primary type.
- Shared protocol changes must compile in both app and helper targets.
- Debug signing: `Apple Development`, automatic. Release: `Developer ID Application`, manual, team `867PL24QLQ`.

## Entry points

- App lifecycle / open-file: `BoxCutter/BoxCutterApp.swift`
- UI root and state routing: `BoxCutter/ContentView.swift`
- Behavior changes (PKG + DMG flows): `BoxCutter/ViewModels/AppViewModel.swift`
- State enum: `BoxCutter/Models/AppState.swift`
- Settings + presets: `BoxCutter/Models/AppSettings.swift` (`AppSettings.shared`, `UserDefaults`-backed)
- PKG install fallback (AppleScript admin): `BoxCutter/Services/DirectInstaller.swift`
- Privileged XPC client: `BoxCutter/Services/XPCClient.swift`
- Helper registration/status: `BoxCutter/Services/HelperManager.swift` (`SMAppService.daemon`)
- DMG mount/copy/quarantine: `BoxCutter/Services/DMGService.swift`
- Helper XPC listener + client validation: `BoxCutter Helper/HelperDelegate.swift`
- Root installer runner: `BoxCutter Helper/InstallerRunner.swift`
- Mach service name: `Shared/SharedConstants.swift`

State machine summary:
- PKG: `idle → inspecting(URL) → packageReady(PackageInfo) → installing → completed | failed`
- DMG: `dmgMounting(URL) → dmgReady(DMGInfo) → dmgInstalling → dmgCompleted([InstalledApp]) | dmgFailed`
- `handleFile(url:)` rejects new input unless state is `.idle`. Preserve this invariant unless adding explicit cancellation.

## Gotchas

- Helper Mach service: `com.hwxnnn.BoxCutter-Helper`. Helper executable is `BoxCutterHelper` (no space — renamed from `"BoxCutter Helper"`); display target dir is still `BoxCutter Helper/`.
- Helper validation in Release requires bundle id `com.hwxnnn.BoxCutter` + Apple generic anchor + matching team ID. Bundle-id-only validation is `#if DEBUG` only — never loosen Release.
- Root/helper cannot reliably read `~/Downloads` or `~/Desktop` due to TCC. PKG installs intentionally copy to `/tmp/BoxCutter-<UUID>-<name>.pkg` first.
- Do not add an overall timeout around the helper install operation. Large packages legitimately exceed 30s; timing out causes duplicate installs. `ping` is only a readiness probe and may fail against older resident helpers — fall through to `installPackage` regardless.
- DMG copy uses `ditto -V` into a hidden staging bundle under `/Applications`, then atomic swap. Pre-existing apps are moved aside to `.BoxCutter-backup-...` before replacement.
- Startup cleanup removes orphaned staging bundles only. **Do not** delete `.BoxCutter-backup-*` — those are user recovery artifacts.
- `isCodeSignatureValid` uses default `SecStaticCodeCheckValidity` flags (not strict/deep) to avoid false negatives on legitimate signed apps.
- `unmount` is fire-and-forget by design (avoids blocking caller threads).
- Helper packaging: main app's Copy Files build phase embeds the helper binary + plist into `Contents/Library/LaunchDaemons`. First-run requires user approval in System Settings → Login Items & Extensions.
- Signed Release builds need the Developer ID private key for team `867PL24QLQ`; otherwise use `CODE_SIGNING_ALLOWED=NO`.
- `DirectInstaller` builds privileged shell commands via AppleScript `quoted form of`. Do not regress to manual string escaping — backticks, `$()`, quotes, spaces, backslashes must not become injection under admin privileges.
- UI is fixed-width (`ContentView` width 400, fixed window). Do not redesign into a landing page.
- `BoxCutter Helper` target's `MACOSX_DEPLOYMENT_TARGET = 26.2` looks anomalous vs main app's `15.0`. TODO(agent): verify whether intentional.

## Don't

- Don't commit: `xcuserdata/`, `*.xcuserstate`, `DerivedData/`, `build/`, `.DS_Store`, `*.moved-aside`, `*.xccheckout`, `*.xcscmblueprint`.
- Don't loosen helper client validation in Release.
- Don't accept arbitrary client-supplied paths or commands across XPC.
- Don't delete `.BoxCutter-backup-*` directories anywhere in code.
- Don't add timeouts wrapping the privileged install call.
- Don't change `HelperProtocol` without updating both targets and considering old-resident-helper compatibility.
- Don't claim sandboxed; project entitlements aren't set for it.
- Don't introduce third-party dependencies or package managers without explicit instruction.
- Don't force-push or rewrite shared history on `main`.
