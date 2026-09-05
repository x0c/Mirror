import AppKit
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

        // 图标即唯一主入口：禁止隐藏；若用户以前藏过，写回可见。
        if !iconStore.isVisible {
            iconStore.isVisible = true
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

        // 冷启动与登录项一律只就绪菜单栏；禁止自动开镜子/摄像头。
        // 仅用户左键、菜单「显示镜像」、或 applicationShouldHandleReopen 才 showMirror()。
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 已在跑时从「应用程序」/ Spotlight 再次打开：用户主动操作，开镜子。
        // 冷启动 / 登录项只走 didFinishLaunching，不会进这里；图标强制可见，无需恢复窗策略。
        mirrorWindowController?.showMirror()
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
