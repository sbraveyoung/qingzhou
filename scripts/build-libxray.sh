#!/usr/bin/env bash
# 构建 LibXray.xcframework（Apple iOS / iossimulator / macOS / maccatalyst slices）。
#
# 用法：
#   ./scripts/build-libxray.sh         # 重新编译
#   ./scripts/build-libxray.sh --clean # 先清理 build 缓存再编
#
# 产物：Frameworks/LibXray.xcframework （~150 MB，不入库 —— 见 .gitignore）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBXRAY_DIR="${LIBXRAY_DIR:-$HOME/code/libXray}"
LIBXRAY_REPO="https://github.com/XTLS/libXray.git"

# 1) 确保 libXray repo clone 好了
if [ ! -d "$LIBXRAY_DIR/.git" ]; then
  echo "==> Cloning libXray to $LIBXRAY_DIR"
  git clone --depth 1 "$LIBXRAY_REPO" "$LIBXRAY_DIR"
fi

# 2) 工具链就绪
export PATH="$HOME/go/bin:$PATH"
if ! command -v go >/dev/null; then
  echo "ERROR: go not in PATH. Run 'brew install go' first." >&2
  exit 1
fi
if ! command -v python3 >/dev/null; then
  echo "ERROR: python3 not available." >&2
  exit 1
fi

# 3) gomobile（libXray 用 Apple 官方 gomobile，不是 sing-box 的 sagernet/gomobile 分支）
if ! [ -x "$HOME/go/bin/gomobile" ]; then
  echo "==> Installing gomobile + gobind"
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
fi

# 4) 可选 --clean
if [ "${1:-}" = "--clean" ]; then
  echo "==> Cleaning libXray go.mod / build artifacts"
  rm -f "$LIBXRAY_DIR/go.mod" "$LIBXRAY_DIR/go.sum"
  rm -rf "$LIBXRAY_DIR/LibXray.xcframework"
fi

# 5) 准备 Go env（手动跑 libXray 的 init_go_env + download_geo，省去走 python 入口）
echo "==> Preparing Go module env"
cd "$LIBXRAY_DIR"
rm -f go.mod go.sum
go mod init github.com/xtls/libxray
go mod tidy
go run download_geo/main.go

# 6) gomobile bind
# 注意：不要带 maccatalyst —— gomobile + Xcode 26 在 maccatalyst 上有
# "duplicate framework path" bug（详见 docs/ROADMAP.md "S1 已知坑"）。
# iossimulator 也只 keep arm64（M1/M2 Mac 走 sim）。
echo "==> Running gomobile bind (this is the long step, 20-40min)"
gomobile bind \
    -target=ios,iossimulator,macos \
    -iosversion=15.0

# 6) 把产物挪到本仓库
SRC="$LIBXRAY_DIR/LibXray.xcframework"
DST="$REPO_ROOT/Frameworks/LibXray.xcframework"
if [ ! -d "$SRC" ]; then
  echo "ERROR: build succeeded but $SRC missing" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/Frameworks"
rm -rf "$DST"
echo "==> Moving xcframework to $DST"
mv "$SRC" "$DST"

echo "==> Done. Size:"
du -sh "$DST"

cat <<EOF

下一步：
  1. 取消 Package.swift 里 XrayCore product + binaryTarget + target 的注释
  2. swift build  → 应该看到 XrayCore 编译过
  3. 在主 app 入口加  Text("xray \(XrayCore.version)")  验证 link 通了

EOF
