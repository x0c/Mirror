import AppKit
import MacKitCore
import MacKitLifecycle
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var mirrorWindowController: MirrorWindowController?
    private var cameraPermissionObserver: NSObjectProtocol?
    private let iconStore = MenuBarIconStore.shared
    private let launchAtLogin = MirrorLaunchAtLogin()
    private let terminationGuard = TerminationGuard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.updaterController.updater.sessionInProgress ?? false
        }

        let sessionManager = CameraSessionManager()
        observeCameraReactivation(sessionManager)

        let windowController = MirrorWindowController(sessionManager: sessionManager)

        mirrorWindowController = windowController
        statusBarController = StatusBarController(
            iconStore: iconStore,
            launchAtLogin: launchAtLogin,
            isVisible: { [weak windowController] in
                windowController?.isVisible ?? false
            },
            toggleVisibility: { [weak windowController] in
                windowController?.toggle()
            },
            showMirror: { [weak windowController] in
                windowController?.showMirror()
            },
            isMirrored: {
                sessionManager.isMirrored
            },
            toggleMirroring: {
                sessionManager.toggleMirroring()
            },
            checkForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            },
            onQuit: { [weak self] in
                self?.terminationGuard.requestTermination()
            }
        )

        windowController.showMirror()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MenuBarReopenPolicy.presentation(iconVisible: iconStore.isVisible, isReopenOrLaunch: true)
            == .showRecoveryWindow {
            mirrorWindowController?.showMirror()
        } else {
            mirrorWindowController?.showMirror()
        }
        return true
    }

    /// 用户去系统设置重新打开摄像头授权后，切回本应用时自动重新检测，
    /// 不需要手动点重试按钮。
    private func observeCameraReactivation(_ sessionManager: CameraSessionManager) {
        cameraPermissionObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak sessionManager] _ in
            Task { @MainActor in
                sessionManager?.recheckAuthorization()
            }
        }
    }
}
