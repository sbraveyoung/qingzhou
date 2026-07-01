# Apps

iOS / macOS app targets。本目录用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理 Xcode 工程 —— 配置在 [`project.yml`](project.yml)，`.xcodeproj` 不入库（由 [.gitignore](../.gitignore) 忽略），每次拉代码自己生成。

## 一次性安装

```bash
brew install xcodegen
```

## 生成 / 重新生成 工程

```bash
cd Apps
xcodegen generate
open Qingzhou.xcodeproj
```

> 任何时候改了 [`project.yml`](project.yml)、加 / 删了源文件、调整了依赖，重跑 `xcodegen generate`。

## Schemes

| Scheme | 用途 |
|---|---|
| `Qingzhou-iOS` | iOS App target，部署 iOS 17+ |
| `Qingzhou-macOS` | macOS App target，部署 macOS 14+ |

## 命令行构建（验证用，不用开 Xcode）

```bash
# macOS（ad-hoc 签名，不用任何账号）
xcodebuild -project Apps/Qingzhou.xcodeproj -scheme Qingzhou-macOS \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

# iOS Simulator
xcodebuild -project Apps/Qingzhou.xcodeproj -scheme Qingzhou-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build
```

## 真机调试

### macOS

开发机本身就是「真机」。`xcodegen generate` → 在 Xcode 打开 `Qingzhou.xcodeproj` → 选 `Qingzhou-macOS` scheme → ⌘R。

> 如果不需要 App Sandbox 限制（比如本地调试想读任意路径），临时把 [macOS/Resources/Qingzhou.entitlements](macOS/Resources/Qingzhou.entitlements) 里 `com.apple.security.app-sandbox` 改 `false`。上架前要改回 `true`。

### iOS

1. **填你的 Team ID**。打开 [project.yml](project.yml)，在 `Qingzhou-iOS` target 的 `settings.base` 里取消注释并填入 `DEVELOPMENT_TEAM: <你的 10 位 Team ID>`。
   - 找 Team ID：Xcode → `Settings → Accounts → 选你的 Apple ID → Team` 那一栏，或 <https://developer.apple.com/account>。
   - 免费 Apple ID 也有 Personal Team，照填即可。
2. `xcodegen generate` 重新生成。
3. 改 Bundle ID 避免和别人冲突：把 `PRODUCT_BUNDLE_IDENTIFIER` 的 `com.example.vpn.ios` 换成你自己的反域名。
4. iPhone 用数据线接电脑，第一次会要求在 iPhone 上确认信任。
5. 打开 `Qingzhou.xcodeproj`，顶部 destination 选你的真机，⌘R。
6. 首次安装后，去 iPhone：`设置 → 通用 → VPN 与设备管理 → 你的开发者账号 → 信任`。

**免费账号限制**：签出来的 app **7 天后失效**，到时再 ⌘R 一次就行。

## 阶段 2：让 VPN 真的工作

阶段 1 的 app 已经能：解析订阅、管理节点、做规则匹配、跑延迟测试、读写日志、设置端口/主题/语言、macOS 状态栏开关 —— 但「VPN 已连接」开关只是个状态位，**流量不会真走代理**。

要让流量真正经过代理：

1. 在 [project.yml](project.yml) 里新增 `Qingzhou-Tunnel` target（type `app-extension`，platform iOS/macOS）；
2. 在 entitlements 里取消 `networkextension` 和 `application-groups` 两行的注释；
3. Apple Developer 后台为对应 App ID 申请 *Network Extensions / Packet Tunnel* capability（人工审核，1–2 周）；
4. 集成 [sing-box](https://github.com/SagerNet/sing-box) 作为协议核心（`gomobile bind` 出 xcframework）；
5. 在 Tunnel target 的 `PacketTunnelProvider.startTunnel` 里桥接 sing-box。

完整步骤见 [../docs/BUILD.md](../docs/BUILD.md#启用真正的-vpn-隧道阶段-2-工作)。

## 目录结构

```
Apps/
├── project.yml                      # XcodeGen 配置
├── iOS/
│   ├── Sources/
│   │   └── VPNiOSApp.swift          # iOS @main 入口
│   └── Resources/
│       └── Assets.xcassets/
└── macOS/
    ├── Sources/
    │   └── VPNMacApp.swift          # macOS @main 入口 + MenuBarExtra
    └── Resources/
        ├── Assets.xcassets/
        └── Qingzhou.entitlements         # 由 XcodeGen 根据 project.yml 重写
```
