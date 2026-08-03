import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var mirrorWindowController: MirrorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let sessionManager = CameraSessionManager()
        let windowController = MirrorWindowController(sessionManager: sessionManager)

        mirrorWindowController = windowController
        statusBarController = StatusBarController(
            isVisible: { [weak windowController] in
                windowController?.isVisible ?? false
            },
            toggleVisibility: { [weak windowController] in
                windowController?.toggle()
            },
            isMirrored: {
                sessionManager.isMirrored
            },
            toggleMirroring: {
                sessionManager.toggleMirroring()
            }
        )
    }
}
