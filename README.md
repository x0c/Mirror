# Mirror

<p align="center">
  <img src="MirrorApp/Assets.xcassets/AppIcon.appiconset/AppIcon-mac-app-512x512@2x.png" alt="Mirror app icon" width="160">
</p>

A simple native macOS camera mirror. Floating preview above other windows, controlled from the menu bar.

## Features

- Menu bar app (no Dock icon)
- Left-click the menu bar icon to open the mirror; right-click for the menu
- Horizontal mirroring toggle
- Floating, resizable, always-on-top preview
- Remembers window position, size, opacity, and mirror preference

## Requirements

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

## License

MIT — see [LICENSE](LICENSE).
