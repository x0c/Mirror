# Mirror 对外分发知识库

## 正式交付标准

Mirror 是公开自分发的 macOS 应用。每个正式版本同时交付两条完整路径：

- 首次安装：公开 Release 内的 `Mirror.dmg`，使用 Developer ID 签名、苹果公证且已装订票据。
- 后续升级：Sparkle 自动更新，源码仓 Release 内的 appcast 与更新包均有 Mirror 专用 EdDSA 签名；更新包内的应用也必须已经完成公证和票据装订。

应用内的更新检查自动开启；菜单栏提供「检查更新…」供用户手动触发。不要用「没有弹窗」判断没有更新，先比较本机内部构建号与公开清单。

## 更新仓边界（强制）

源码仓已公开，更新清单（appcast）与已签名包必须发在本仓 Release，**禁止另建 `xxx-updates` 更新仓**。旧 `x0c/Mirror-updates` 已归档，仅作老版本历史下载源。

## 发布入口

执行 `scripts/publish-release.sh` 完成完整发布；`--local-only` 仅生成并验证本地可分发的 DMG。脚本会检查版本回退、Developer ID 签名、加固运行时、**摄像头 entitlement**、调试权限、公证结果、票据、安装启动、GitHub Release 以及匿名下载。

创建公开发行页时不要把安装包写进同一条命令（会 404 或只留下其中一个文件）。先建空页，再逐个上传；匿名下载若刚建完报 404，等几秒重试，不要重做公证。2026-09-02 的 1.0.8 发行页当时立刻拉首装包失败，稍后匿名下载已通。

**加固运行时与摄像头是两道独立门禁。** Release 必须开启加固运行时才能公证；加固运行时默认禁止访问摄像头，签名里必须带 `com.apple.security.device.camera`（工程文件 `MirrorApp/Mirror.entitlements`）。只在 Info.plist 写用途说明、只让用户在系统设置里打开开关，正式包仍会显示「未获得摄像头权限」。Debug 默认不开加固运行时，本机调试过不代表公证包能用摄像头。

版本号由 `project.yml` 的展示版本和内部构建号共同定义，二者均须递增。严禁把更新清单写回低于已公开版本的构建号。

## 公开地址

- 首装包：`https://github.com/x0c/Mirror/releases/latest/download/Mirror.dmg`
- 更新清单：`https://github.com/x0c/Mirror/releases/latest/download/appcast.xml`

两者都在源码仓 Release，无独立更新仓。

## 安全与隐私边界

摄像头画面和用户偏好始终只在本机处理。应用仅在检查或下载更新时访问公开分发服务。更新签名私钥只能保存在本机钥匙串，苹果公证密钥只能保存在本机私有密钥目录；两者均不得写进仓库、日志或发布说明。

<!-- 该文档整理/压缩于 2026-09-05 -->

## Settings delivery diagnostics (2026-10-19)

Settings releases must commit and push the complete source before building/installing, retain complete archive/export diagnostics (not redirect compiler output to `/dev/null`), and build both arm64 and x86_64. The release runner may continue in a detached Python `start_new_session=True` process during Apple notarization; reuse accepted/stapled artifacts after an attachment-only failure. Release notes are English first followed by complete Simplified Chinese. Anonymous acceptance compares downloaded DMG and ZIP bytes and the signed appcast against the actual release artifacts.

Diagnostic assessment for the settings retrofit: fresh Debug build and static analysis passed with no Swift compiler/analyzer diagnostics. Xcode selected the first of two architecture destinations for `platform=macOS`; use an explicit architecture for subsequent Debug checks and a generic universal archive for delivery. AppIntents metadata extraction was skipped because Mirror does not link AppIntents or define intents; no app feature depends on that metadata. This tool-generated warning remains acceptable until intent support exists. Full log: `/tmp/mirror-settings-build.log` on the acceptance host (temporary evidence, not a portable artifact).

The fresh universal archive also exposed missing LSApplicationCategoryType. Set the native Utilities category in project.yml (generated Info.plist) before publication; the prior accepted app submission is retained as superseded, not reused for changed bundle bytes. The macOS 27.2 hdiutil-create deprecation originates in the system packaging CLI: it still creates a validated UDZO image; retain this tooling warning for this release, with migration to the installed diskutil-image command deferred until its complete create/sign/notarize path is validated. No runtime app behavior depends on that CLI.

## 1.0.13 delivery evidence

Universal arm64/x86_64 archive/export succeeded from committed source a1e863b; the missing-category diagnostic is resolved. Final app notarization b736dec7-3b04-4550-abd5-fc0048c60184 and DMG notarization 4dc22382-3fd5-46d6-9115-162f8abf5737 were Accepted. The stapled final app is installed at /Applications/Mirror.app; deep/strict signature and staple validation passed, and the freshly reopened installed Settings window was inspected at 480×258 points. Screenshot: `images/settings.png`. Static light English/Chinese acceptance is complete; dark, physical keyboard/VoiceOver, login-approval and older-OS limits above remain.

[Public release 1.0.13](https://github.com/x0c/Mirror/releases/tag/v1.0.13) contains DMG, ZIP and signed appcast. Anonymous downloads exactly matched local bytes: DMG SHA-256 dc39d76d5b6a245da73b0840c3241d417566fcbf2c751e6a8acacf8d5e18ca81; ZIP 8293511c666c08c660d09c505098143f78d2ce50dabeeab574c98eefb97486c1. The plain latest-feed URL was independently rechecked at build 14. GitHub’s API already reported the new release while the anonymous latest redirect still returned the old tag; refreshing latest and rechecking resolved it. This was an attachment/feed visibility check, requiring no app rebuild or repeated notarization. Full diagnostic logs remain under ignored `build/settings-delivery-1.0.13/` and `build/archive.log`.

The reusable diagnosis and recovery are owned by the shared [anonymous latest-feed acceptance procedure](~/Codes/_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md#anonymous-latest-feed-acceptance); the IDs, checksums and installed evidence above remain product-specific.
