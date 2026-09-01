# AGENTS.md

本文件面向会在本仓库内工作的代码代理（LLM / Coding Agent）。

通用工程规范：[Swift 规范](../_standards/swift.md)（新建/改造 SwiftUI 与 AppKit 层、权限、发布、macOS 交互习惯）

## 1. 项目定位

Mirror 是一个简单的 macOS 原生摄像头镜像工具，使用 SwiftUI 构建。

- 简洁：提供基础的摄像头预览。
- 高效：支持全屏、缩放、置顶预览。
- 原生：符合 macOS 应用规范。

## 当前交付边界与数据处理

**本应用正式对外自分发。**首装必须提供 Developer ID 签名、苹果公证并装订票据的 DMG；后续升级必须通过 Sparkle 的 EdDSA 签名更新清单完成。每次发布都要同时验证陌生用户可匿名下载的 DMG 与更新清单，不能只验证本机构建。

- 保存的数据：镜像开关、窗口位置和尺寸、透明度等预览偏好，仅保存在这台 Mac 的本地偏好存储。
- 当前未发现的行为：不上传摄像头画面或上述偏好，也不建立网络连接。摄像头权限只用于本地实时预览；若后续增加录制、导出、网络传输、遥测或第三方服务，必须先重新核对这段说明与隐私声明，不能沿用「纯本机」结论。
- 改造发布、更新或首装链路时，**必须先读并落实** [签名、公证与分发指南](../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md)——自行分发须完成 Developer ID 签名、公证及可获得的安全更新路径；若改走 Mac App Store，则按商店更新路径验收。同时重新按实际数据收集、权限与第三方依赖核对隐私说明和 macOS 基线，完成真实安装与升级验证后才能公开。

### 文档导航

> 以下文档在涉及对应领域的开发、评审或排查时**必读**（先读再动手，避免踩线程模型、状态机、几何交互等隐性约束）：

- `docs/CAMERA_SESSION_KNOWLEDGE_BASE.md`：摄像头权限状态机、采集会话配置与生命周期、设备选择、中心舞台、权限降级与恢复
- `docs/MIRROR_WINDOW_KNOWLEDGE_BASE.md`：镜像窗口几何交互（拖拽/缩放/透明度）、位置持久化、圆形裁剪预览、隐藏时机
- `docs/MENU_BAR_ENTRY_KNOWLEDGE_BASE.md`：改、评审或排查菜单栏入口、状态栏图标、左右键分发、菜单项状态同步、应用生命周期与权限恢复观察前必读；否则会把 App Icon 直接缩小成菜单栏图、破坏左键直达镜像或漏掉深浅色模板验收
- `docs/DISTRIBUTION_KNOWLEDGE_BASE.md`：改、评审、排查或发布首装包、签名、公证、应用内更新时**必读**；否则会发布无法安装或无法升级的版本。

## 2026-09-01 菜单栏专项复核：已在 Mac 落地

已补隐藏/恢复菜单栏图标；左键仍直达镜像、右键仍打开菜单。开机自启待批准不能显示成已开启。本机已覆盖安装 1.0.8 (9)。藏图标找回未再复测（一次藏多个会把本机打满）；左键仍开镜子。公开更新三种网络结果与重新登录未测。

## 2. 修改要求

- 改动前先阅读相关文件，基于现有结构扩展，不要凭空重写。
- 不要覆盖或回退你未创建的用户改动。
- 优先做小步、清晰、可验证的修改。
- UI 代码保持 macOS 原生桌面应用语义，不要写成 iOS 风格页面。
- 若修改工程结构，先维护 `project.yml`，再执行 `xcodegen generate` 同步工程。

## 3. 改动完成后的强制动作

只要你改动了仓库中的代码文件，就必须在结束前执行一次“杀掉旧进程 -> 构建 -> 移动到 Applications -> 拉起 /Applications 里面的新应用 -> 校验进程”的完整流程。

说明：

- “代码文件”指会影响应用行为的文件，例如 `swift`、工程配置、资源等。
- 如果只修改文档文件（例如 `README.md`、`AGENTS.md`），不要求执行这套流程。

### 3.1 构建环境

固定使用完整 Xcode：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Mirror.xcodeproj -scheme Mirror -configuration Debug -derivedDataPath .build build
```

要求：

- 构建失败时，停止后续启动流程。
- 构建失败时，要输出失败结论，并说明没有启动新版本应用。
- 不要在构建失败后继续保留“可预览”的错误表述。

### 3.2 固定重启流程

构建成功后，必须先关闭旧进程，再将应用移动/替换到 `/Applications` 里面，最后启动 `/Applications` 里面的新 app：

```bash
pkill -x Mirror || true
rm -rf /Applications/Mirror.app
cp -R .build/Build/Products/Debug/Mirror.app /Applications/
open /Applications/Mirror.app
```

启动后必须补一条检查，确认新进程真的起来了：

```bash
pgrep -fal '/Applications/Mirror.app/Contents/MacOS/Mirror'
```

要求：

- 先停旧进程，再开新进程。
- 必须先把编译好的 app 移动/替换到 `/Applications` 里面。
- 必须启动 `/Applications/Mirror.app`，不要启动其他路径下的历史包。
- 如果 `open` 成功但进程没有起来，必须继续排查，不能直接声称“已经启动”。

### 3.3 推荐的一次性完整命令顺序

在仓库根目录推荐按下面顺序执行：

```bash
pkill -x Mirror || true
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Mirror.xcodeproj -scheme Mirror -configuration Debug -derivedDataPath .build build
rm -rf /Applications/Mirror.app
cp -R .build/Build/Products/Debug/Mirror.app /Applications/
open /Applications/Mirror.app
pgrep -fal '/Applications/Mirror.app/Contents/MacOS/Mirror'
```

### 3.4 最终汇报要求

在最终回复中明确说明：

- 改了什么。
- 是否执行了构建。
- 是否成功移动并拉起 /Applications 里面的新进程。
- 是否验证到新进程 PID 或产物路径。
- 如果没做到，阻塞点是什么。

## 领域地图（doc-init）

<!-- 覆盖度复核基线：2026-08-08 · 源码指纹 6 个 Swift 文件 + Info.plist（git 跟踪共 14 文件）/ Swift 6 · 0 子模块 · 基线提交 4eb911f -->

| 领域 | 入口锚点 |
|------|---------|
| 摄像头采集与权限 | MirrorApp/CameraSessionManager.swift |
| 镜像窗口与交互 | MirrorApp/MirrorWindowController.swift · MirrorApp/CameraPreviewView.swift |
| 菜单栏入口与生命周期 | MirrorApp/StatusBarController.swift · MirrorApp/AppDelegate.swift · MirrorApp/MirrorApp.swift |
