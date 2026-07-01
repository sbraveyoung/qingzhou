# 构建

## 前置要求

| 工具 | 最低版本 | 备注 |
|---|---|---|
| macOS | 14.0 | 用于编译，跑 macOS 版 |
| Xcode | 16.0 | 提供 Swift 6 工具链 + iOS 17 / macOS 14 SDK |
| Swift | 6.0 | 包含在 Xcode 里 |

> 当前仓库由 Xcode 26.4.1 / Swift 6.3.1 验证通过。

## 编译核心库

```bash
swift build              # 默认 Debug
swift build -c release   # Release
```

输出在 `.build/<arch>-apple-macosx/<config>/`，每个库一个 `.swiftmodule` + `.o`。

## 跑测试

```bash
swift test               # 跑全部 73 个单测
swift test --filter QingzhouRulesTests          # 跑某个 target
swift test --parallel                      # 并行（默认就是并行）
```

## 跨平台编译

### iOS（device + simulator）

```bash
xcodebuild -scheme Qingzhou-Package \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/iOS-derived build

xcodebuild -scheme Qingzhou-Package \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/iOS-sim-derived build
```

### macOS

```bash
swift build              # 等价
```

### Linux（核心库部分）

`QingzhouCore` / `QingzhouProtocols` / `QingzhouSubscription` / `QingzhouRules` / `QingzhouSpeedTest` / `QingzhouLogging` 不依赖 SwiftUI 与 AppKit/UIKit，理论上能在 Linux 上编译（CI 用得到）。`QingzhouApp` 因为引入了 SwiftUI 不能在 Linux 上编译。

```bash
# 在 Linux 上需要修改 Package.swift，去掉 QingzhouApp target 和它的测试。
```

## 集成进 iOS / macOS App

仓库自带 `Apps/project.yml`，用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 一条命令生成 `.xcodeproj`：

```bash
brew install xcodegen     # 一次性安装
cd Apps
xcodegen generate
open Qingzhou.xcodeproj        # iOS / macOS 两个 target 都在里面
```

Schemes：`Qingzhou-iOS`、`Qingzhou-macOS`。详细的真机调试 / 签名 / Bundle ID 修改步骤见 [../Apps/README.md](../Apps/README.md)。

## 启用真正的 VPN 隧道（阶段 2 工作）

### 4) 添加 Packet Tunnel Provider Extension

- `File → New → Target → Network Extension`
- Provider Type：`Packet Tunnel`
- 这会生成一个新 target（比如 `VPNTunnel`）和一个 `*.entitlements`。

### 5) 配置 entitlements

主 App target 和 Tunnel target 都要勾选以下 capabilities：

```
com.apple.developer.networking.networkextension = [packet-tunnel-provider]
com.apple.security.application-groups = ["group.com.you.vpn"]
```

> 个人开发者只能用 Personal VPN（`personal-vpn`），Packet Tunnel 需要企业账号或单独走 Apple 申请流程：
> <https://developer.apple.com/contact/request/networking-entitlement>

### 6) 集成 sing-box 作为协议核心

```bash
# 假设你的 GOPATH 已就绪
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
gomobile bind -target=ios,iossimulator,macos \
  -o Frameworks/SingBox.xcframework \
  github.com/sagernet/sing-box/experimental/libbox
```

把 `SingBox.xcframework` 拖到 Xcode 项目，分别勾选主 App 和 Tunnel target。

### 7) 在 PacketTunnelProvider 里桥接

```swift
import NetworkExtension
import QingzhouCore

final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 1. 从 App Group 共享容器读取节点配置 + 规则
        // 2. 用 sing-box 的 LibBox.start(...) 起核心
        // 3. 用 self.setTunnelNetworkSettings(...) 把虚拟接口配上
        // 4. 起协程读 packetFlow → 喂给 sing-box；反向同理
    }
}
```

详细的 sing-box 桥接代码在阶段 2 的提交里会引入。

### 8) macOS 系统代理 + 开机自启

```swift
import ServiceManagement

// 开机自启（macOS 13+）
try SMAppService.mainApp.register()

// 系统代理：执行 networksetup 命令或用 SCDynamicStore API
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
task.arguments = ["-setwebproxy", "Wi-Fi", "127.0.0.1", "\(httpPort)"]
try task.run()
```

## 常见问题

### `dependency 'X' is not found`
- `swift package reset && swift package resolve`。

### iOS 模拟器跑不起来 Network Extension
- 真实的 Packet Tunnel **只能在真机上跑**，模拟器不会触发 VPN 框架。
- 模拟器里可以验证 UI 和所有非隧道功能。

### Xcode 抱怨 "Provisioning profile doesn't include packet-tunnel-provider"
- 去 Apple Developer 后台为对应 App ID 启用 Network Extensions capability。
- 个人账号只能用 Personal VPN（足够做 OpenVPN 类配置但不能写 PacketTunnel）。
