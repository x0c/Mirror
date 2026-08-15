import AppKit
import ServiceManagement
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let sessionManager = CameraSessionManager()
        observeCameraReactivation(sessionManager)

        let windowController = MirrorWindowController(sessionManager: sessionManager)

        mirrorWindowController = windowController
        statusBarController = StatusBarController(
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
            launchAtLoginStatus: {
                SMAppService.mainApp.status
            },
            setLaunchAtLoginEnabled: { enabled in
                do {
                    switch (enabled, SMAppService.mainApp.status) {
                    case (true, .notRegistered), (true, .notFound):
                        try SMAppService.mainApp.register()
                    case (false, .enabled), (false, .requiresApproval):
                        try SMAppService.mainApp.unregister()
                    default:
                        break
                    }
                } catch {
                    NSLog("Mirror 开机自启动设置失败：%@", error.localizedDescription)
                }
            },
            checkForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            }
        )

        windowController.showMirror()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
