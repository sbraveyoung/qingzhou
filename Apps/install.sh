#!/usr/bin/env bash
# 一键构建 + 安装 VPN-macOS.app 到 /Applications。
#
# 用法：
#   ./install.sh              # ad-hoc 签名（默认；UI 能跑；VPN 开关会报 permission denied）
#   ./install.sh --signed     # Apple Developer 真签名（VPN 真能用，必须有付费账号）
#
# VPN 隧道真要工作，必须用 --signed —— macOS 不接受 ad-hoc 签名 app 写 VPN 配置。

set -euo pipefail

cd "$(dirname "$0")"

SIGNED_MODE=0
if [ "${1:-}" = "--signed" ]; then
  SIGNED_MODE=1
fi

# 1) 停掉正在跑的 app
echo "==> Stopping any running instance"
killall VPN-macOS 2>/dev/null || true

# 2) 重新生成 Xcode 工程
echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

# 3) 构建
BUILD_DIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$BUILD_DIR'" EXIT

if [ "$SIGNED_MODE" = "1" ]; then
  echo "==> Building Release (Apple Developer signed; needs Xcode logged into Apple ID)"
  # -allowProvisioningUpdates 让 xcodebuild 在 profile 缺失时自动创建
  # Team ID 从 project.yml 来；这里再保险写一遍
  xcodebuild -project VPN.xcodeproj -scheme VPN-macOS \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=UK7MME38H9 \
    build 2>&1 | tail -5
else
  echo "==> Building Release (ad-hoc; VPN tunnel won't work — use --signed for real VPN)"
  xcodebuild -project VPN.xcodeproj -scheme VPN-macOS \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tail -3
fi

APP_SRC="$BUILD_DIR/Build/Products/Release/VPN-macOS.app"
APP_DST="/Applications/VPN-macOS.app"

if [ ! -d "$APP_SRC" ]; then
  echo "ERROR: build artifact not found at $APP_SRC" >&2
  exit 1
fi

# 4) 装到 /Applications
echo "==> Installing to $APP_DST"
if [ ! -w /Applications ]; then
  APP_DST="$HOME/Applications/VPN-macOS.app"
  mkdir -p "$HOME/Applications"
fi
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

# 5) 去 quarantine（ad-hoc 模式下必要；真签名也不害事）
xattr -cr "$APP_DST"

# 6) 启动
echo "==> Launching"
open "$APP_DST"

sleep 1
PID=$(pgrep -f VPN-macOS | head -1 || true)
if [ -n "${PID:-}" ]; then
  echo "==> Done. PID=$PID  →  $APP_DST"
  if [ "$SIGNED_MODE" = "1" ]; then
    cat <<EOF

    🔐 第一次开 VPN 开关时 macOS 会弹「VPN-macOS 想要添加 VPN 配置 / 输入密码」
    输入你的 Mac 登录密码 → 允许
    之后如果还报 permission denied，去：
      系统设置 → 隐私与安全性 → 最下面有"VPN 配置已被阻止"红字 → 点"允许"

EOF
  else
    cat <<EOF

    ⚠️  你跑的是 ad-hoc 签名版本 —— UI 能看，VPN 开关会报 "permission denied"。
    要让 VPN 真生效，用：  ./install.sh --signed

EOF
  fi
else
  echo "==> Built and installed at $APP_DST  (app did not stay alive; check Console.app)"
fi
