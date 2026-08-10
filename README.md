# Mirror

<p align="center">
  <img src="MirrorApp/Assets.xcassets/AppIcon.appiconset/AppIcon-mac-app-512x512@2x.png" alt="Mirror app icon" width="160">
</p>

A simple native macOS camera mirror. Floating preview above other windows, controlled from the menu bar.

## 安装

下载最新版 [Mirror.dmg](https://github.com/x0c/Mirror/releases/latest/download/Mirror.dmg)，打开后将 Mirror 拖入“应用程序”文件夹即可。安装包已经过 Apple Developer ID 签名与苹果公证。

应用会在后台自动检查并安全安装后续更新；也可以从菜单栏中选择“检查更新…”。

## Features

- Menu bar app (no Dock icon)
- Left-click the menu bar icon to open the mirror; right-click for the menu
- Horizontal mirroring toggle
- Floating, resizable, always-on-top preview
- Remembers window position, size, opacity, and mirror preference

## 开发环境

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
git clone https://github.com/x0c/Mirror.git
cd Mirror
xcodegen generate
open Mirror.xcodeproj
```

Or from the CLI:

```bash
xcodegen generate
xcodebuild -project Mirror.xcodeproj -scheme Mirror -configuration Debug build
```

## Usage

1. Run the app — a menu bar icon appears (no Dock icon).
2. Grant **Camera** access when prompted.
3. Left-click the icon to open the mirror; right-click for show/hide, mirroring, and Quit.
4. Drag to move; drag edges/corners to resize.

## Privacy & permissions

- Camera access is required for the live preview.
- Preferences (window frame, opacity, mirroring) are stored locally in `UserDefaults`.
- No network access; nothing is uploaded.

应用仅在检查和下载更新时连接公开更新服务，不会上传摄像头画面或偏好设置。

## License

MIT — see [LICENSE](LICENSE).
