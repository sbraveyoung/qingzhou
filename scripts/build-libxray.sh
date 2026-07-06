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
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
if ! command -v go >/dev/null; then
  echo "ERROR: go not in PATH. Run 'brew install go' first." >&2
  exit 1
fi
if ! command -v python3 >/dev/null; then
  echo "ERROR: python3 not available." >&2
  exit 1
fi

# go install 的落点：尊重用户的 GOBIN / GOPATH（比如本机 GOPATH=~/code → 二进制在
# ~/code/bin），不能硬编码 ~/go/bin —— 之前硬编码导致 gomobile 装好了却 command not found
GOBIN_DIR="$(go env GOBIN)"
[ -z "$GOBIN_DIR" ] && GOBIN_DIR="$(go env GOPATH)/bin"
export PATH="$GOBIN_DIR:$PATH"

# 3) gomobile（libXray 用 Apple 官方 gomobile，不是 sing-box 的 sagernet/gomobile 分支）
if ! command -v gomobile >/dev/null; then
  echo "==> Installing gomobile + gobind (into $GOBIN_DIR)"
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
# go 1.26+ 的 gomobile 要求 golang.org/x/mobile 在模块依赖图里（tool directive），
# 而本脚本每次重建 go.mod，必须显式加回去，否则 bind 直接报 missing dependency
go get -tool golang.org/x/mobile/cmd/gobind
go run download_geo/main.go

# 5.5) macOS 内存压制 patch —— 上游只给 iOS（//go:build ios）内置了
# GOMEMLIMIT/GOGC/FreeOSMemory 压制，macOS slice 走 memory_other.go 的 no-op，
# Go 堆会无约束增长（实测扩展 RSS 爬到 1.6GB）。这里在 bind 前把本仓库
# scripts/patches/libxray/ 下的两个文件覆盖进去：
#   memory_macos.go  darwin && !ios：SetMemoryLimit(192MiB) + GOGC=30 + 10s FreeOSMemory
#   memory_other.go  !ios && !darwin：no-op（收窄上游的 !ios，避免重复定义）
# build tag 互斥，iOS 构建（memory_ios.go）完全不受影响。取值理由见 patch 文件头注释。
# 若上游改动 memory/ 包导致编译失败，先看 patches/ 与上游是否需要同步。
echo "==> Applying macOS memory-suppression patch (scripts/patches/libxray/)"
cp "$REPO_ROOT/scripts/patches/libxray/memory_macos.go" "$LIBXRAY_DIR/memory/memory_macos.go"
cp "$REPO_ROOT/scripts/patches/libxray/memory_other.go" "$LIBXRAY_DIR/memory/memory_other.go"

# 5.6) xray-core fakedns 崩溃修复 —— backport 上游 XTLS/Xray-core@7ab0a3c (#6022)：
# fakedns Holder.Close() 把 map/锁置 nil，与 dispatcher sniffer 在途的
# GetDomainFromFakeDNS 竞态 → 整个扩展进程 panic（实录单日 6 次崩溃报告）。
# 做法：把模块缓存里的 xray-core 原版复制成本地目录、覆盖单文件补丁，再用
# go.mod replace 指过去。⚠️ 本脚本每次重建 go.mod，replace 必须在这里重加，
# 否则构建产物会悄悄退回带崩溃的原版。升级 xray-core 版本时：改 XC_VER +
# 确认上游是否已含该修复（含则删掉本节 + scripts/patches/xray-core/）。
XC_VER="v1.260327.0"
XC_PATCHED="$LIBXRAY_DIR/.xray-core-patched-$XC_VER"
if [ ! -d "$XC_PATCHED" ]; then
  echo "==> Creating patched xray-core copy ($XC_VER)"
  go mod download github.com/xtls/xray-core
  XC_CACHE="$(go env GOMODCACHE)/github.com/xtls/xray-core@$XC_VER"
  [ -d "$XC_CACHE" ] || { echo "ERROR: $XC_CACHE not in module cache (版本对不上？改 XC_VER)" >&2; exit 1; }
  mkdir -p "$XC_PATCHED"
  cp -R "$XC_CACHE/." "$XC_PATCHED/"
  chmod -R u+w "$XC_PATCHED"
fi
echo "==> Applying fakedns crash fix (scripts/patches/xray-core/) + go.mod replace"
cp "$REPO_ROOT/scripts/patches/xray-core/fake.go" "$XC_PATCHED/app/dns/fakedns/fake.go"
go mod edit -replace "github.com/xtls/xray-core=$XC_PATCHED"
go mod tidy

# 5.7) 无感换节点 patch —— 轻舟自定义 libXray 导出 SwitchOutbound：在运行中的
# xray 实例上热替换 "proxy" outbound handler（隧道/路由/DNS 全不动，换节点零断流）。
# Swift 侧对应 XrayCore.switchOutbound → 扩展 handleAppMessage "switchNode"。
echo "==> Applying switch-outbound patch (scripts/patches/libxray/qingzhou_switch*.go)"
cp "$REPO_ROOT/scripts/patches/libxray/qingzhou_switch.go" "$LIBXRAY_DIR/xray/qingzhou_switch.go"
cp "$REPO_ROOT/scripts/patches/libxray/qingzhou_switch_wrapper.go" "$LIBXRAY_DIR/qingzhou_switch_wrapper.go"

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
