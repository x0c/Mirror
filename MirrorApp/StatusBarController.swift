import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let toggleVisibilityHandler: () -> Void
    private let isVisibleHandler: () -> Bool
    private let toggleMirroringHandler: () -> Void
    private let isMirroredHandler: () -> Bool

    private lazy var visibilityItem = NSMenuItem(
        title: "显示镜像",
        action: #selector(handleToggleVisibility),
        keyEquivalent: ""
    )
    private lazy var mirroringItem = NSMenuItem(
        title: "水平镜像",
        action: #selector(handleToggleMirroring),
        keyEquivalent: ""
    )

    init(
        isVisible: @escaping () -> Bool,
        toggleVisibility: @escaping () -> Void,
        isMirrored: @escaping () -> Bool,
        toggleMirroring: @escaping () -> Void
    ) {
        self.isVisibleHandler = isVisible
        self.toggleVisibilityHandler = toggleVisibility
        self.isMirroredHandler = isMirrored
        self.toggleMirroringHandler = toggleMirroring
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "camera.macro.circle.fill",
            accessibilityDescription: "Mirror"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        visibilityItem.target = self
        mirroringItem.target = self

        let quitItem = NSMenuItem(
            title: "退出 Mirror",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.delegate = self
        menu.addItem(visibilityItem)
        menu.addItem(mirroringItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        // Intentionally do not assign `statusItem.menu` so left-click can open Mirror.
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        visibilityItem.title = isVisibleHandler() ? "隐藏镜像" : "显示镜像"
        mirroringItem.state = isMirroredHandler() ? .on : .off
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            openMirrorIfNeeded()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showMenu(from: sender)
        default:
            openMirrorIfNeeded()
        }
    }

    private func openMirrorIfNeeded() {
        if isVisibleHandler() {
            return
        }
        toggleVisibilityHandler()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let location = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    @objc
    private func handleToggleVisibility() {
        toggleVisibilityHandler()
    }

    @objc
    private func handleToggleMirroring() {
        toggleMirroringHandler()
    }

    @objc
    private func handleQuit() {
        NSApp.terminate(nil)
    }
}
