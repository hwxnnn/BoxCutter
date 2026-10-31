import Foundation
import Darwin

/// Exercises the production preference/state flow with isolated UserDefaults.
/// Real DMG apps install only into fresh temporary directories, never /Applications.
@main
struct UniversalStrippingPreferenceTests {
    enum Failure: Error { case check(String) }

    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.check(message) }
        print("PASS: \(message)")
    }

    @MainActor
    static func ready(_ vm: AppViewModel, image: URL) async throws -> DMGInfo {
        vm.loadDMG(url: image)
        for _ in 0..<600 {
            if case .dmgReady(let info) = vm.state { return info }
            if case .dmgFailed(let message) = vm.state { throw Failure.check(message) }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.check("Timed out inspecting the fixture")
    }

    @MainActor
    static func main() async throws {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    static func completed(_ vm: AppViewModel) async throws -> [InstalledApp] {
        for _ in 0..<600 {
            if case .dmgCompleted(let apps, _) = vm.state {
                try check(vm.dmgInstallErrors.isEmpty, "fixture apps install without errors")
                return apps
            }
            if case .dmgFailed(let message) = vm.state { throw Failure.check(message) }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.check("Timed out installing the temporary fixture")
    }

    @MainActor
    static func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.check("Pass the Impactor DMG path") }
        let suite = "BoxCutter.UniversalStrippingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.playSoundOnComplete = false
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("BoxCutter-thinning-flow-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        print("Isolated installs: \(root.path)")
        func makeVM() throws -> AppViewModel {
            let destination = root.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            return AppViewModel(settings: settings, applicationsDirectory: destination)
        }
        let vm = try makeVM()
        let image = URL(fileURLWithPath: CommandLine.arguments[1])
        try check(settings.universalAppThinningMode == .ask && !settings.hasChosenUniversalAppStripping, "fresh preferences default to Ask and retain the first-use alert")
        let mountedInfo = try await ready(vm, image: image)
        try check(vm.showUniversalStripPrompt, "first universal DMG presents the one-time alert")
        try check(vm.universalStripPromptMessage == "This app contains code for Intel based Mac devices, which your Mac doesn't need.\n\nWould you like to strip it out to save 17.8 MB?", "first-use alert retains the paragraph break and measured saving")
        vm.chooseUniversalAppStripping(.no)
        guard case .dmgReady(let declined) = vm.state else { throw Failure.check("First-use No unexpectedly installed an app") }
        try check(!vm.showUniversalStripPrompt && declined.appIDsToThin.isEmpty, "first-use No returns to the normal preview")
        try check(AppSettings(defaults: defaults).hasChosenUniversalAppStripping, "first-use choice persists across launches")

        // Keep an immutable local fixture so state tests never race image teardown.
        let fixtureDirectory = root.appendingPathComponent("fixture")
        try fm.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fixture = fixtureDirectory.appendingPathComponent("Impactor.app")
        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        copy.arguments = [mountedInfo.apps[0].appURL.path, fixture.path]
        try copy.run()
        copy.waitUntilExit()
        guard copy.terminationStatus == 0 else { throw Failure.check("Could not prepare the fixture") }
        var info = mountedInfo
        info.apps = try DMGService.findApps(at: fixtureDirectory)
        info.selectedAppIDs = Set(info.apps.map(\.appURL))
        info.appIDsToThin = []
        info.appIDsWithThinningDecision = []

        let yes = try makeVM()
        yes.prepareDMGInstall(info)
        try check(yes.state == .dmgReady(info) && !yes.showUniversalStripPrompt, "Ask shows the preview without a thinning question")
        yes.installSelected()
        guard case .dmgThinningChoice = yes.state else { throw Failure.check("Install did not open the main-window question") }
        let question = yes.state
        yes.handleFile(url: image)
        yes.installSelected()
        try check(yes.state == question, "new input and duplicate Install cannot bypass an open thinning question")
        yes.chooseDMGThinning(true)
        guard case .dmgInstalling(let thinned) = yes.state else { throw Failure.check("Yes did not continue the approved install") }
        try check(thinned.appIDsToThin == info.selectedAppIDs, "Yes continues installation with thinning")
        let thinApps = try await completed(yes)
        let thinArchitectures = Set(Bundle(url: thinApps[0].installedURL)?.executableArchitectures?.map(\.intValue) ?? [])
        let nativeCPU = BinaryArchitecture.native == .arm64 ? NSBundleExecutableArchitectureARM64 : NSBundleExecutableArchitectureX86_64
        try check(thinArchitectures == [nativeCPU], "main-window Yes installs only native code in the temporary destination")

        settings.confirmBeforeDMGInstall = false
        let no = try makeVM()
        no.prepareDMGInstall(info)
        try check(no.state == .dmgReady(info), "Ask retains the Install button even when ordinary confirmation is off")
        no.installSelected()
        no.chooseDMGThinning(false)
        guard case .dmgInstalling(let kept) = no.state else { throw Failure.check("No did not continue the approved install") }
        try check(kept.appIDsToThin.isEmpty, "No continues installation without thinning")
        let keptApps = try await completed(no)
        let keptArchitectures = Set(Bundle(url: keptApps[0].installedURL)?.executableArchitectures?.map(\.intValue) ?? [])
        try check(keptArchitectures == [NSBundleExecutableArchitectureARM64, NSBundleExecutableArchitectureX86_64], "main-window No preserves both architectures")
        settings.confirmBeforeDMGInstall = true

        let cancel = try makeVM()
        cancel.prepareDMGInstall(info)
        cancel.installSelected()
        cancel.cancelDMG()
        try check(cancel.state == .idle, "Cancel exits the question without installing")

        settings.universalAppThinningMode = .always
        let always = try makeVM()
        always.prepareDMGInstall(info)
        always.installSelected()
        guard case .dmgInstalling(let automatic) = always.state else { throw Failure.check("Always unexpectedly asked a question") }
        try check(automatic.appIDsToThin == info.selectedAppIDs && !always.showUniversalStripPrompt, "Always thins without a question")
        _ = try await completed(always)
        try check(AppSettings(defaults: defaults).universalAppThinningMode == .always, "Always is persisted")

        settings.universalAppThinningMode = .never
        let never = try makeVM()
        never.prepareDMGInstall(info)
        never.installSelected()
        guard case .dmgInstalling(let unmodified) = never.state else { throw Failure.check("Never unexpectedly asked a question") }
        try check(unmodified.appIDsToThin.isEmpty && !never.showUniversalStripPrompt, "Never preserves all code without a question")
        _ = try await completed(never)
        try check(AppSettings(defaults: defaults).universalAppThinningMode == .never, "Never is persisted")

        settings.universalAppThinningMode = .ask
        vm.state = .dmgReady(info)
        vm.showUniversalStripPrompt = true
        vm.chooseUniversalAppStripping(.yes)
        guard case .dmgReady(let firstYes) = vm.state else { throw Failure.check("First-use Yes skipped the preview") }
        try check(firstYes.appIDsToThin == info.selectedAppIDs && settings.universalAppThinningMode == .ask, "first-use Yes applies only to the current install")
        vm.state = .dmgReady(info)
        vm.showUniversalStripPrompt = true
        vm.chooseUniversalAppStripping(.always)
        try check(settings.universalAppThinningMode == .always, "first-use Always selects the Always dropdown option")
        vm.reset()
        settings.resetToDefaults()
        try check(settings.universalAppThinningMode == .ask && !settings.hasChosenUniversalAppStripping, "Restore Defaults resets to Ask and re-enables first-use guidance")

        let migrationSuite = suite + ".migration"
        let migration = UserDefaults(suiteName: migrationSuite)!
        defer { migration.removePersistentDomain(forName: migrationSuite) }
        migration.set(true, forKey: "stripUniversalApps")
        try check(AppSettings(defaults: migration).universalAppThinningMode == .always, "migrate the legacy enabled toggle to Always")
        migration.set(false, forKey: "stripUniversalApps")
        try check(AppSettings(defaults: migration).universalAppThinningMode == .ask, "migrate the legacy disabled toggle to Ask")
        migration.set("never", forKey: "universalAppThinningMode")
        migration.set(true, forKey: "stripUniversalApps")
        try check(AppSettings(defaults: migration).universalAppThinningMode == .never, "an explicit dropdown value takes precedence over the legacy toggle")
        try check(AppSettings.UniversalAppThinningMode.allCases.map(\.title) == ["Ask", "Always", "Never"], "dropdown offers Ask, Always, Never in order")
        try headerChecks()
    }

    static func headerChecks() throws {
        func header(wide: Bool, littleEndian: Bool) -> Data {
            var data = Data()
            func append(_ value: UInt64, bytes: Int) {
                for index in 0..<bytes {
                    let shift = (littleEndian ? index : bytes - 1 - index) * 8
                    data.append(UInt8(truncatingIfNeeded: value >> shift))
                }
            }
            append(wide ? 0xcafebabf : 0xcafebabe, bytes: 4)
            append(2, bytes: 4)
            for (cpu, offset, size) in [(UInt64(0x01000007), UInt64(4096), UInt64(4096)), (UInt64(0x0100000c), UInt64(8192), UInt64(2048))] {
                append(cpu, bytes: 4); append(0, bytes: 4)
                append(offset, bytes: wide ? 8 : 4); append(size, bytes: wide ? 8 : 4)
                append(12, bytes: 4)
                if wide { append(0, bytes: 4) }
            }
            return data
        }
        for wide in [false, true] {
            for littleEndian in [false, true] {
                let data = header(wide: wide, littleEndian: littleEndian)
                try check(UniversalBinary.removableBytes(in: data, fileSize: 10240, keeping: .arm64) == 8192, "parse \(wide ? 64 : 32)-bit FAT headers (little endian: \(littleEndian))")
                try check(UniversalBinary.removableBytes(in: data, fileSize: 10240, keeping: .x86_64) == 6144, "estimate retained Intel slice correctly")
                try check(UniversalBinary.removableBytes(in: data.prefix(12), fileSize: 10240, keeping: .arm64) == 0, "reject truncated FAT tables")
                try check(UniversalBinary.removableBytes(in: data, fileSize: 9000, keeping: .arm64) == 0, "reject slices outside the file")
            }
        }
        var malformed = header(wide: false, littleEndian: false)
        malformed.replaceSubrange(4..<8, with: [0xff, 0xff, 0xff, 0xff])
        try check(UniversalBinary.removableBytes(in: malformed, fileSize: 10240, keeping: .arm64) == 0, "bound architecture counts before reading records")
    }
}
