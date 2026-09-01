import AppKit
import Combine
import Foundation
import MacKitCore
import MacKitLaunchAtLogin

/// 菜单栏图标显隐。缺省为显示；用键是否存在判断，避免把空当成关。
@MainActor
final class MenuBarIconStore: ObservableObject {
    static let shared = MenuBarIconStore()
    static let key = "menuBar.iconVisible"

    @Published var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.key)
            onChange?(isVisible)
        }
    }

    var onChange: ((Bool) -> Void)?

    init() {
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            isVisible = true
        } else {
            isVisible = UserDefaults.standard.bool(forKey: Self.key)
        }
    }
}

/// 开机自启薄封装，把待批准从「已开启」里拆出来。
@MainActor
final class MirrorLaunchAtLogin {
    private let service = LaunchAtLoginService()

    var status: LaunchAtLoginStatus {
        service.status
    }

    func refresh() {
        service.refresh()
    }

    func setEnabled(_ enabled: Bool) {
        if service.needsApproval, enabled {
            service.openSystemSettings()
            service.refresh()
            return
        }
        _ = service.setEnabled(enabled)
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
