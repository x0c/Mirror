#!/usr/bin/env bash
# Mirror 正式自分发：归档导出、签名校验、公证和装订、DMG、Sparkle 更新清单、GitHub 发布。
# 用法：scripts/publish-release.sh [--local-only]
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
ARCHIVE_PATH="${BUILD_DIR}/Mirror.xcarchive"
EXPORT_DIR="${BUILD_DIR}/Export"
APP_PATH="${EXPORT_DIR}/Mirror.app"
SIGN_IDENTITY="Developer ID Application"
NOTARY_KEY="${NOTARY_KEY:-${HOME}/Documents/P8 密钥/发布公证密钥/AuthKey_D7YQ9HD7D6_Notarize.p8}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-D7YQ9HD7D6}"
NOTARY_ISSUER="${NOTARY_ISSUER:-c98fe4b8-d1bf-4b4a-b998-9eb8f3be9fe4}"
UPDATE_REPO="x0c/Mirror-updates"
UPDATE_FEED_URL="https://github.com/${UPDATE_REPO}/releases/latest/download/appcast.xml"
SPARKLE_ACCOUNT="Mirror"
LOCAL_ONLY=false
[[ "${1:-}" == "--local-only" ]] && LOCAL_ONLY=true

die() { printf '发布失败：%s\n' "$*" >&2; exit 1; }
step() { printf '\n▶ %s\n' "$*"; }

notarize_and_wait() {
  local target="$1" result submission_id status
  result="$(xcrun notarytool submit "$target" --wait --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --output-format json)" \
    || die "苹果公证未通过：${target}"
  submission_id="$(jq -r '.id // empty' <<<"$result")"
  status="$(jq -r '.status // empty' <<<"$result")"
  [[ "$status" == "Accepted" ]] || die "苹果公证状态异常：${status:-未知}（提交编号：${submission_id:-未知}）"
  printf '苹果公证通过，提交编号：%s\n' "$submission_id"
}

cd "$ROOT_DIR"
[[ -f "$NOTARY_KEY" ]] || die "找不到苹果公证密钥"
identities="$(security find-identity -v -p codesigning)"
grep -q "$SIGN_IDENTITY" <<<"$identities" || die "找不到 Developer ID 签名身份"
xcrun notarytool history --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" >/dev/null \
  || die "苹果公证凭据不可用"

version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)"
build_number="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)"
[[ -n "$version" && "$build_number" =~ ^[0-9]+$ ]] || die "无法读取有效版本号"
dmg_path="${BUILD_DIR}/Mirror.dmg"
zip_path="${BUILD_DIR}/Mirror-${version}.zip"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

if [[ "$LOCAL_ONLY" == false ]] && curl -fsSL "$UPDATE_FEED_URL" -o "$work_dir/current-appcast.xml" 2>/dev/null; then
  published_build="$(xmllint --xpath 'string((//*[local-name()="version"] | //@*[local-name()="version"])[1])' "$work_dir/current-appcast.xml" 2>/dev/null || true)"
  [[ ! "$published_build" =~ ^[0-9]+$ || "$build_number" -ge "$published_build" ]] \
    || die "拒绝把公开更新清单回退到较低构建号"
fi

step "生成工程并按 Developer ID 归档导出"
xcodegen generate >/dev/null
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
xcodebuild -project Mirror.xcodeproj -scheme Mirror -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" -archivePath "$ARCHIVE_PATH" -allowProvisioningUpdates ARCHS=arm64 archive >/dev/null
cat > "$work_dir/ExportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>SHZQ3MWP3B</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Developer ID Application</string>
<key>destination</key><string>export</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$work_dir/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates >/dev/null
[[ -d "$APP_PATH" ]] || die "Developer ID 导出产物不存在"

step "校验应用和内嵌更新组件签名"
sign_info="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1)"
entitlements="$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null || true)"
grep -q "Authority=${SIGN_IDENTITY}" <<<"$sign_info" || die "应用未使用 Developer ID 签名"
grep -q 'flags=.*runtime' <<<"$sign_info" || die "应用未开启加固运行时"
! grep -q 'get-task-allow' <<<"$entitlements" || die "应用带有调试权限"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null
sparkle_bin_dir="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$sparkle_bin_dir/generate_appcast" ]] || die "找不到 Sparkle 发布工具"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' MirrorApp/Info.plist)"
[[ "$("$sparkle_bin_dir/generate_keys" --account "$SPARKLE_ACCOUNT" -p)" == "$public_key" ]] \
  || die "更新签名私钥与应用公钥不匹配"

step "公证应用并装订票据"
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/Mirror-notarize.zip"
notarize_and_wait "$BUILD_DIR/Mirror-notarize.zip"
xcrun stapler staple "$APP_PATH" >/dev/null
xcrun stapler validate "$APP_PATH" >/dev/null

step "生成已装订票据的自动更新包"
rm -f "$zip_path"
ditto -c -k --keepParent "$APP_PATH" "$zip_path"

step "制作、公证并装订首装 DMG"
stage_dir="$work_dir/dmg"
mkdir -p "$stage_dir"
ditto "$APP_PATH" "$stage_dir/Mirror.app"
ln -s /Applications "$stage_dir/应用程序"
rm -f "$dmg_path"
hdiutil create -volname Mirror -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path" >/dev/null
notarize_and_wait "$dmg_path"
xcrun stapler staple "$dmg_path" >/dev/null
xcrun stapler validate "$dmg_path" >/dev/null
spctl -a -vvv -t install "$dmg_path" >/dev/null

step "覆盖安装最终应用并启动验证"
pkill -x Mirror || true
rm -rf /Applications/Mirror.app
ditto "$APP_PATH" /Applications/Mirror.app
codesign --verify --deep --strict --verbose=2 /Applications/Mirror.app >/dev/null
open /Applications/Mirror.app
sleep 2
pgrep -fal '/Applications/Mirror.app/Contents/MacOS/Mirror' >/dev/null || die "最终应用未能从应用程序目录启动"

if [[ "$LOCAL_ONLY" == true ]]; then
  printf '本地发布验证完成：%s\n' "$dmg_path"
  exit 0
fi

step "提交源码、创建标签并发布首装包"
git add -A
git commit -m "发布 Mirror ${version}" || true
git tag -a "v${version}" -m "Mirror ${version}" 2>/dev/null || true
git push origin main --follow-tags
gh release create "v${version}" "$dmg_path#Mirror.dmg" --repo x0c/Mirror --title "Mirror ${version}" --notes "- 正式提供已签名并公证的 DMG 首装包。\n- 支持安全的应用内自动更新。" 2>/dev/null \
  || gh release upload "v${version}" "$dmg_path#Mirror.dmg" --repo x0c/Mirror --clobber

step "生成并发布签名更新清单"
update_dir="$work_dir/Mirror-updates"
git clone "https://github.com/${UPDATE_REPO}.git" "$update_dir" >/dev/null
appcast_dir="$work_dir/appcast"
mkdir -p "$appcast_dir"
cp "$zip_path" "$appcast_dir/Mirror-${version}.zip"
if [[ -f "$update_dir/appcast.xml" ]]; then cp "$update_dir/appcast.xml" "$appcast_dir/appcast.xml"; fi
"$sparkle_bin_dir/generate_appcast" --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/${UPDATE_REPO}/releases/download/v${version}/" \
  --versions "$build_number" --maximum-versions 10 -o "$appcast_dir/appcast.xml" "$appcast_dir" >/dev/null
xmllint --noout "$appcast_dir/appcast.xml"
grep -q 'sparkle:edSignature=' "$appcast_dir/appcast.xml" || die "更新清单缺少 EdDSA 签名"
grep -q 'sparkle-signatures:' "$appcast_dir/appcast.xml" || die "更新清单本身未签名"
cp "$appcast_dir/appcast.xml" "$update_dir/appcast.xml"
git -C "$update_dir" add appcast.xml
git -C "$update_dir" commit -m "发布 Mirror ${version} 更新清单" || true
git -C "$update_dir" push origin main
gh release create "v${version}" "$zip_path#Mirror-${version}.zip" "$appcast_dir/appcast.xml#appcast.xml" \
  --repo "$UPDATE_REPO" --title "Mirror ${version} 更新" --notes "Mirror ${version} 的签名自动更新包。" 2>/dev/null \
  || gh release upload "v${version}" "$zip_path#Mirror-${version}.zip" "$appcast_dir/appcast.xml#appcast.xml" --repo "$UPDATE_REPO" --clobber

step "匿名终检公开安装包与更新清单"
curl -fsSL "https://github.com/x0c/Mirror/releases/download/v${version}/Mirror.dmg" -o "$work_dir/anonymous.dmg"
curl -fsSL "$UPDATE_FEED_URL" -o "$work_dir/anonymous-appcast.xml"
xmllint --noout "$work_dir/anonymous-appcast.xml"
grep -q "Mirror-${version}.zip" "$work_dir/anonymous-appcast.xml" || die "公开更新清单没有当前更新包"
grep -q 'sparkle:edSignature=' "$work_dir/anonymous-appcast.xml" || die "公开更新清单缺少更新签名"
printf '\n发布完成：首装包 https://github.com/x0c/Mirror/releases/latest/download/Mirror.dmg\n更新清单 %s\n' "$UPDATE_FEED_URL"
