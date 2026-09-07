import AppKit
import MacKitCore
import MacKitLifecycle
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供设置窗调用；SwiftUI 生命周期下对 `NSApp.delegate` 转型常会失败。
    private(set) static weak var shared: AppDelegate?

    private var statusBarController: StatusBarController?
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var mirrorWindowController: MirrorWindowController?
    private var cameraSessionManager: CameraSessionManager?
    private var cameraPermissionObserver: NSObjectProtocol?
    private let iconStore = MenuBarIconStore.shared
    private let launchAtLogin = MirrorLaunchAtLogin()
    private let terminationGuard = TerminationGuard()
    /// 后台就绪时刻；二次启动防呆用。
    private var becameReadyAt: Date?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.updaterController.updater.sessionInProgress ?? false
        }

        // 图标即唯一主入口：禁止隐藏；若用户以前藏过，写回可见。
        if !iconStore.isVisible {
            iconStore.isVisible = true
        }

        let sessionManager = CameraSessionManager()
        cameraSessionManager = sessionManager
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
            openSettings: { [weak self] in
                self?.openSettings()
            },
            checkForUpdates: { [weak self] in
                self?.checkForUpdates()
            },
            onQuit: { [weak self] in
                self?.requestTermination()
            }
        )

        // 冷启动与登录项一律只就绪菜单栏；禁止自动开镜子/摄像头。
        becameReadyAt = Date()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 菜单栏即主入口：就绪后默认 60 秒内再次打开须出配置窗（不论图标是否可见）。
        let elapsed = becameReadyAt.map { Date().timeIntervalSince($0) }
        if MenuBarReopenPolicy.presentation(
            iconVisible: iconStore.isVisible,
            isReopenOrLaunch: true,
            menubarIsPrimaryEntry: true,
            secondsSinceReady: elapsed
        ) == .showRecoveryWindow {
            openSettings()
        }
        return true
    }

    func showMirror() {
        mirrorWindowController?.showMirror()
    }

    func toggleMirrorVisibility() {
        mirrorWindowController?.toggle()
    }

    func isMirrorVisible() -> Bool {
        mirrorWindowController?.isVisible ?? false
    }

    func isMirrored() -> Bool {
        cameraSessionManager?.isMirrored ?? true
    }

    func toggleMirroring() {
        cameraSessionManager?.toggleMirroring()
    }

    func launchAtLoginSnapshot() -> (isOn: Bool, needsApproval: Bool) {
        launchAtLogin.refresh()
        let status = launchAtLogin.status
        return (status.isEffectivelyEnabled, status == .needsApproval)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.refresh()
        launchAtLogin.setEnabled(enabled)
    }

    func openLoginItemsSettings() {
        launchAtLogin.openSystemSettings()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func requestTermination() {
        terminationGuard.requestTermination()
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
