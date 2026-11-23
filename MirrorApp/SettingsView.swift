import AppKit
import MacKitUpdater
import SwiftUI

struct SettingsView: View {
    @State private var isMirrored = true
    @State private var mirrorVisible = false
    @State private var launchAtLoginOn = false
    @State private var launchNeedsApproval = false
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        sizedForm
            .frame(width: 480)
            .fixedSize()
            .focusEffectDisabled()
            .background(SettingsWindowObserver())
            .onAppear(perform: refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh()
            }
            .onExitCommand { SettingsWindowController.shared.close() }
    }

    @ViewBuilder
    private var sizedForm: some View {
        if #available(macOS 15, *) {
            settingsForm
                .onScrollGeometryChange(for: CGFloat.self) { ceil($0.contentSize.height) } action: { _, height in
                    if height > 0 { contentHeight = height }
                }
                .frame(height: contentHeight)
        } else {
            settingsForm.frame(height: 350)
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                LabeledContent("settings.preview") {
                    Button(mirrorVisible ? String(localized: "settings.hide") : String(localized: "settings.show")) {
                        if mirrorVisible {
                            AppDelegate.shared?.toggleMirrorVisibility()
                        } else {
                            AppDelegate.shared?.showMirror()
                        }
                        refresh()
                    }
                }

                Toggle("settings.horizontal_mirroring", isOn: Binding(
                    get: { isMirrored },
                    set: { _ in
                        AppDelegate.shared?.toggleMirroring()
                        refresh()
                    }
                ))
            }

            Section {
                Toggle("settings.launch_at_login", isOn: Binding(
                    get: { launchAtLoginOn },
                    set: { enabled in
                        AppDelegate.shared?.setLaunchAtLogin(enabled)
                        refresh()
                    }
                ))

                if launchNeedsApproval {
                    LabeledContent {
                        Button("settings.open_system_settings") {
                            AppDelegate.shared?.openLoginItemsSettings()
                        }
                    } label: {
                        Label {
                            Text("settings.approval_required").foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section { aboutRow }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
    }

    private var aboutRow: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Mirror").fontWeight(.medium)
                Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            UpdateCheckButton(availability: AppDelegate.shared?.updateAvailability)
            Button("settings.quit") { AppDelegate.shared?.requestTermination() }
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

private struct UpdateCheckButton: View {
    let availability: UpdateAvailabilityState?

    var body: some View {
        Button(title) {
            AppDelegate.shared?.checkForUpdates()
        }
    }

    private var title: String {
        if let version = availability?.availableVersion {
            return String(format: String(localized: "settings.install_update"), version)
        }
        return String(localized: "settings.check_for_updates")
    }
}
