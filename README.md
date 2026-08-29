<p align="center">
  <img src="assets/BoxCutter Icon.png" width="128" height="128" alt="BoxCutter Icon">
</p>

<h1 align="center">BoxCutter</h1>

<p align="center">
How installing apps should be on macOS<br>
Drop a <code>.pkg</code> or <code>.dmg</code> — BoxCutter installs it in seconds, no friction.
</p>

<p align="center">
No more double-clicking disk images, dragging to Applications, unmounting volumes,<br>
or running through multi-step installer wizards. Just drop and go.<br>
Fully vibecoded. Sorry.
</p>

---

## Screenshots

<table>
  <tr>
    <td align="center"><img src="assets/main-view.png" width="300"><br><sub>Drop Zone</sub></td>
    <td align="center"><img src="assets/pkg-preview.png" width="300"><br><sub>.pkg Preview</sub></td>
    <td align="center"><img src="assets/dmg-preview.png" width="300"><br><sub>.dmg Preview</sub></td>
  </tr>
</table>

## Features

**Instant drag-and-drop**
Drop any `.pkg` installer or `.dmg` disk image onto the window. BoxCutter takes care of everything from there.

**One-step DMG installs**
No more mounting, dragging to Applications, and ejecting. BoxCutter mounts the image, finds the app, copies it, and unmounts automatically.

**Package inspection**
View metadata, payload files, and pre/post-install script warnings before committing to a `.pkg` install.

**Parallel DMG app installs**
When a disk image contains multiple apps, BoxCutter installs them all concurrently.

**Privileged Helper**
A dedicated launchd daemon handles elevated-privilege package installs via XPC, keeping root operations out of the main app process.

**Quarantine fix**
One-click removal of the macOS quarantine flag on apps installed from DMGs.

**Safety profiles**
Maximum, Balanced, or Fast presets control confirmation prompts and post-install cleanup.

**Verbose output**
Real-time installer logs and a progress bar during `.pkg` installations.

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 16+ to build from source

## Building

1. Clone the repository.
2. Open `BoxCutter.xcodeproj` in Xcode.
3. Select your Development Team in the project settings for both the **BoxCutter** and **BoxCutter Helper** targets.
4. Build (`Cmd + B`).
The Privileged Helper is embedded automatically during the build process.
