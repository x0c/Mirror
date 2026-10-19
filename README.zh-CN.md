# Mirror

<p align="center"><img src="docs/images/app-icon.png" alt="Mirror 应用图标" width="160"></p>

原生 macOS 摄像头镜像工具，提供可缩放、置顶的预览窗口和菜单栏入口。

[English](README.md)

## 安装

需要 macOS 14 或更高版本。下载并打开已签名、公证的安装镜像：

```bash
curl -fL https://github.com/x0c/Mirror/releases/latest/download/Mirror.dmg -o /tmp/Mirror.dmg && open /tmp/Mirror.dmg
```

将 Mirror 拖入“应用程序”。后续更新通过应用内签名更新源提供。

## 使用

1. 启动后只就绪菜单栏图标，不打开摄像头。
2. 左键点击图标显示或隐藏镜像，首次使用时允许摄像头权限。
3. 右键菜单可进入设置、切换水平镜像、开机自启、检查更新和退出。
4. 拖动预览移动窗口，拖动边缘或角落缩放。

窗口位置、尺寸、透明度和镜像偏好保存在本机。

## 设置

![Mirror 设置](docs/images/settings.png)

## 构建

需要 Xcode 26 或更高版本及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
git clone https://github.com/x0c/Mirror.git
cd Mirror
xcodegen generate
xcodebuild -project Mirror.xcodeproj -scheme Mirror -configuration Debug build
```

## 隐私

摄像头画面和偏好仅在本机处理。应用只在检查、下载更新时连接公开分发服务，不上传摄像头画面或偏好。

## 许可

MIT，见 [LICENSE](LICENSE)。
