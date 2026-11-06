import AppKit
import Combine
import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's standard updater so the rest of the app stays Sparkle-agnostic.
///
/// The updater starts whenever the app runs from a packaged bundle that declares a `SUFeedURL`. Only
/// `script/make_dmg.sh` bakes one in, so a bare `swift run` and the dev build leave the updater dormant.
/// See `docs/updates.md` for the user-facing behavior.
///
/// It is also both of Sparkle's delegates. `SPUUpdaterDelegate` is main-actor isolated in Sparkle;
/// `SPUStandardUserDriverDelegate` is nonisolated, so its methods are `nonisolated` here and assume the
/// main actor, which Sparkle calls them on.
@MainActor
@Observable
final class UpdaterController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: AnyCancellable?

    var canCheckForUpdates = false
    var availableUpdateVersion: String?

    func start() {
        guard controller == nil else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            AppLog.info(.updates, "disabled: no SUFeedURL (unbundled or dev build)")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.canCheckForUpdates = value }
            }
        AppLog.info(.updates, "started (feed present)")
    }

    func checkForUpdates() {
        guard let controller else { return }
        // Sparkle 2.9.4 also activates dockless apps with `ignoringOtherApps`, but promote Brim
        // before handing control over so the activation-policy transition cannot leave Sparkle's
        // checking window behind the currently active app. The next-runloop handoff mirrors the
        // workaround verified in sparkle-project/Sparkle#2889.
        bringToFront(reason: "user initiated check")
        DispatchQueue.main.async {
            controller.checkForUpdates(nil)
        }
    }

    func dismissAvailableUpdate() {
        availableUpdateVersion = nil
    }

    /// The app runs as an accessory (no Dock icon), so Sparkle's update window would open behind
    /// everything and without focus. Become a regular app while the update UI is on screen.
    /// `NSApplication.activate()` is unreliable when another app is active (sparkle-project/Sparkle#2889),
    /// so this deliberately uses the older API that ignores the current foreground app.
    private func bringToFront(reason: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.info(.updates, "foreground updater (reason=\(reason))")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let error else {
            AppLog.info(.updates, "check finished (no error)")
            return
        }
        let code = (error as NSError).code
        if code == Int(SUError.noUpdateError.rawValue) {
            AppLog.info(.updates, "check finished (no update available)")
        } else if code == Int(SUError.installationCanceledError.rawValue) {
            AppLog.info(.updates, "check finished (user canceled)")
        } else {
            AppLog.warn(.updates, "check/download failed: \(error.localizedDescription)")
        }
    }

    /// A menu-bar app rarely quits, so waiting for that would strand a downloaded update. Install now and
    /// relaunch, unless the panel is in use: then it waits for quit, and the next check offers it again.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard NSApp.keyWindow == nil else {
            AppLog.info(.updates, "\(item.displayVersionString) ready; panel in use, waiting")
            return false
        }
        AppLog.info(.updates, "installing \(item.displayVersionString) and relaunching")
        immediateInstallHandler()
        return true
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Take over showing *scheduled* updates entirely: for a dockless app macOS would put Sparkle's
    /// window behind everything (even the "immediate focus" launch case is unreliable), so instead of
    /// a buried window the update surfaces as the in-popover banner. User-initiated checks never reach
    /// this method — Sparkle always shows those itself, in front.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            guard handleShowingUpdate else {
                availableUpdateVersion = version
                AppLog.info(.updates, "scheduled check found \(version); showing in-app banner")
                return
            }
            bringToFront(reason: "Sparkle will show update")
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            availableUpdateVersion = nil
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            AppLog.info(.updates, "finish updater presentation")
            availableUpdateVersion = nil
        }
    }
}
