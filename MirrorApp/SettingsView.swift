import SwiftUI

/// 配置窗：右键菜单能力的对等入口（裁定 2026-09-07）。
struct SettingsView: View {
    @State private var isMirrored = true
    @State private var mirrorVisible = false
    @State private var launchAtLoginOn = false
    @State private var launchNeedsApproval = false

    var body: some View {
        Form {
            Section {
                Button(mirrorVisible ? "隐藏镜像" : "显示镜像") {
                    if mirrorVisible {
                        AppDelegate.shared?.toggleMirrorVisibility()
                    } else {
                        AppDelegate.shared?.showMirror()
                    }
                    refresh()
                }

                Toggle("水平镜像", isOn: Binding(
                    get: { isMirrored },
                    set: { _ in
                        AppDelegate.shared?.toggleMirroring()
                        refresh()
                    }
                ))

                Toggle("开机时启动 Mirror", isOn: Binding(
                    get: { launchAtLoginOn },
                    set: { enabled in
                        AppDelegate.shared?.setLaunchAtLogin(enabled)
                        refresh()
                    }
                ))

                if launchNeedsApproval {
                    Text("系统仍在等待批准开机启动。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("前往系统设置完成开机启动批准") {
                        AppDelegate.shared?.openLoginItemsSettings()
                    }
                }
            }

            Section {
                Button("检查更新…") {
                    AppDelegate.shared?.checkForUpdates()
                }
                Button("退出 Mirror") {
                    AppDelegate.shared?.requestTermination()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isMirrored = AppDelegate.shared?.isMirrored() ?? true
        mirrorVisible = AppDelegate.shared?.isMirrorVisible() ?? false
        let status = AppDelegate.shared?.launchAtLoginSnapshot()
        launchAtLoginOn = status?.isOn ?? false
        launchNeedsApproval = status?.needsApproval ?? false
    }
}
