# Mirror 对外分发知识库

## 正式交付标准

Mirror 是公开自分发的 macOS 应用。每个正式版本同时交付两条完整路径：

- 首次安装：公开 Release 内的 `Mirror.dmg`，使用 Developer ID 签名、苹果公证且已装订票据。
- 后续升级：Sparkle 自动更新，源码仓 Release 内的 appcast 与更新包均有 Mirror 专用 EdDSA 签名；更新包内的应用也必须已经完成公证和票据装订。

应用内的更新检查自动开启；菜单栏提供「检查更新…」供用户手动触发。不要用「没有弹窗」判断没有更新，先比较本机内部构建号与公开清单。

## 更新仓边界（强制）

源码仓已公开，更新清单（appcast）与已签名包必须发在本仓 Release，**禁止另建 `xxx-updates` 更新仓**（全局规范与《GitHub 开源发布指南》同此要求）。2026-08-17 起已从 `x0c/Mirror-updates` 迁回本仓；旧更新仓在最终清单指向 v1.0.7 后归档，仅作为老版本包的历史下载源保留。

## 发布入口

执行 `scripts/publish-release.sh` 完成完整发布；`--local-only` 仅生成并验证本地可分发的 DMG。脚本会检查版本回退、Developer ID 签名、加固运行时、**摄像头 entitlement**、调试权限、公证结果、票据、安装启动、GitHub Release 以及匿名下载。

**加固运行时与摄像头是两道独立门禁。** Release 必须开启加固运行时才能公证；加固运行时默认禁止访问摄像头，签名里必须带 `com.apple.security.device.camera`（工程文件 `MirrorApp/Mirror.entitlements`）。只在 Info.plist 写用途说明、只让用户在系统设置里打开开关，正式包仍会显示「未获得摄像头权限」。Debug 默认不开加固运行时，本机调试过不代表公证包能用摄像头。

版本号由 `project.yml` 的展示版本和内部构建号共同定义，二者均须递增。严禁把更新清单写回低于已公开版本的构建号。

## 公开地址

- 首装包：`https://github.com/x0c/Mirror/releases/latest/download/Mirror.dmg`
- 更新清单：`https://github.com/x0c/Mirror/releases/latest/download/appcast.xml`

两者都在源码仓 Release，无独立更新仓。

## 安全与隐私边界

摄像头画面和用户偏好始终只在本机处理。应用仅在检查或下载更新时访问公开分发服务。更新签名私钥只能保存在本机钥匙串，苹果公证密钥只能保存在本机私有密钥目录；两者均不得写进仓库、日志或发布说明。
