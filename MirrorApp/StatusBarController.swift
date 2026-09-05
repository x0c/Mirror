import AppKit
import MacKitCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let toggleVisibilityHandler: () -> Void
    private let showMirrorHandler: () -> Void
    private let isVisibleHandler: () -> Bool
    private let toggleMirroringHandler: () -> Void
    private let isMirroredHandler: () -> Bool
    private let launchAtLogin: MirrorLaunchAtLogin
    private let checkForUpdatesHandler: () -> Void
    private let onQuit: () -> Void
    private let iconStore: MenuBarIconStore

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
    private lazy var launchAtLoginItem = NSMenuItem(
        title: "开机时启动 Mirror",
        action: #selector(handleToggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private lazy var approveLaunchAtLoginItem = NSMenuItem(
        title: "前往系统设置完成开机启动批准",
        action: #selector(handleOpenLoginItemsSettings),
        keyEquivalent: ""
    )
    private lazy var checkForUpdatesItem = NSMenuItem(
        title: "检查更新…",
        action: #selector(handleCheckForUpdates),
        keyEquivalent: ""
    )

    init(
        iconStore: MenuBarIconStore,
        launchAtLogin: MirrorLaunchAtLogin,
        isVisible: @escaping () -> Bool,
        toggleVisibility: @escaping () -> Void,
        showMirror: @escaping () -> Void,
        isMirrored: @escaping () -> Bool,
        toggleMirroring: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.iconStore = iconStore
        self.launchAtLogin = launchAtLogin
        self.isVisibleHandler = isVisible
        self.toggleVisibilityHandler = toggleVisibility
        self.showMirrorHandler = showMirror
        self.isMirroredHandler = isMirrored
        self.toggleMirroringHandler = toggleMirroring
        self.checkForUpdatesHandler = checkForUpdates
        self.onQuit = onQuit
        super.init()
        iconStore.onChange = { [weak self] visible in
            self?.statusItem.isVisible = visible
        }
        // 图标即唯一主入口：启动时强制可见，不对外提供隐藏。
        statusItem.isVisible = true
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(named: NSImage.Name("StatusBarIcon")) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            button.image = image
        } else {
            NSLog("Mirror 菜单栏图标加载失败")
        }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.focusRingType = .none
    }

    private func configureMenu() {
        visibilityItem.target = self
        mirroringItem.target = self
        launchAtLoginItem.target = self
        approveLaunchAtLoginItem.target = self
        checkForUpdatesItem.target = self

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
        menu.addItem(launchAtLoginItem)
        menu.addItem(approveLaunchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        // 故意不把菜单挂到状态栏按钮上，这样左键单击可以直接打开镜像窗口。
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        visibilityItem.title = isVisibleHandler() ? "隐藏镜像" : "显示镜像"
        mirroringItem.state = isMirroredHandler() ? .on : .off
        launchAtLogin.refresh()
        launchAtLoginItem.state = launchAtLogin.status.menuTriState.controlState
        approveLaunchAtLoginItem.isHidden = !launchAtLogin.status.needsApprovalMapped
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
        showMirrorHandler()
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
    private func handleToggleLaunchAtLogin() {
        launchAtLogin.refresh()
        launchAtLogin.setEnabled(!launchAtLogin.status.isEffectivelyEnabled)
    }

    @objc
    private func handleOpenLoginItemsSettings() {
        launchAtLogin.openSystemSettings()
    }

    @objc
    private func handleCheckForUpdates() {
        checkForUpdatesHandler()
    }

    @objc
    private func handleQuit() {
        onQuit()
    }
}

private extension LaunchAtLoginStatus {
    var needsApprovalMapped: Bool { self == .needsApproval }
}

private extension MenuTriState {
    var controlState: NSControl.StateValue {
        switch self {
        case .on: return .on
        case .off: return .off
        case .mixed: return .mixed
        }
    }
}
