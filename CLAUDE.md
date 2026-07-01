# 轻舟 / Qingzhou — 关键约定（踩过的坑，别再踩）

## ⚠️ 头号坑：改配置必须改 `project.yml`，不是改生成的文件

本项目用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理工程，`Apps/project.yml` 是**权威源**。
每个 target 的 `entitlements.properties` 和 `info.properties` 会被 `xcodegen generate`
**每次都用来重新生成** `.entitlements` 和 `Info.plist` 文件。

**所以：直接改 `.entitlements` / `Info.plist` 文件，下一次 `xcodegen generate` 会把它覆盖掉，白改。**
要改这些，**改 `project.yml` 的 properties**。

反复踩过的实例（都浪费了很多轮才定位）：
- **App Group 每次 generate 后消失** → 因为只改了 4 个 `.entitlements` 文件，没写进 `project.yml` 的 `entitlements.properties`
- **Launch screen 配置丢失** → 只改了 `Info.plist`，没改 `project.yml` 的 `info.properties`

## App Group —— appex ↔ 主 App 通信的地基

- id：`group.com.sbraveyoung.qingzhou`
- 配在 `project.yml` **4 个 target**（Qingzhou-iOS / Qingzhou-macOS / Qingzhou-Tunnel-iOS / Qingzhou-Tunnel-macOS）的 `entitlements.properties`
- 用途：流量统计（`traffic-stats.json`）+ xray access log 都靠它在扩展进程和主 App 之间共享
- **没配好 → 流量波形、连接列表、域名分析全部无数据**（appex 写不进、主 App 读不到，容器是 nil）
- Apple 后台还要：两个 App ID 都 **Edit/关联** 到这个 group，再刷新 provisioning profile

## appex 代码（`Apps/Tunnel-Shared/`）`swift build` 编不到

- `PacketTunnelProvider.swift` 等在 Xcode target 里，`swift build` / `swift test` **覆盖不到**，改了只能 Xcode 编
- **必须真机验证** —— VPN 扩展在模拟器跑不了
- ⌘R 跑 **Qingzhou-iOS** 会自动连带编译内嵌的 Qingzhou-Tunnel-iOS（`embed: true`），不用单独 build tunnel
- 装完要**关开一次 VPN**，运行中的旧扩展进程才会换成新代码
- Xcode 的 Swift 6 strict concurrency 比命令行严，容易在这里才暴露：闭包捕获可变变量、
  定时器和阻塞 read 循环共用一个串行队列被饿死（导致速率算错）等

## UI / 资源

- **Launch screen 用 `Apps/iOS/Resources/LaunchScreen.storyboard`**，别用 `Info.plist` 的
  `UILaunchScreen` dict —— 它的 `UIImageName` 会把图全屏拉伸，不可控。改了要删 app + 重启手机清缓存
- **toolbar 里别放 `NavigationLink`**（iOS 会渲染出双返回按钮），用 `.navigationDestination(isPresented:)`
- 图标：源在 `docs/icon/*.svg`，用 AppKit（`NSImage` 支持 SVG）渲染成各尺寸 asset PNG

## 数据来源（别再被示例数据坑）

真隧道数据都经 App Group 传：
- **流量统计**（波形 / 字节）：appex 在 TUN socketpair 层数字节 → `traffic-stats.json`
- **连接列表 / 域名分析**：xray `log.access` → access log 文件 → 主 App `AccessLogParser` 解析
- 早期的 `sampleConnectionsLoop` 示例数据（写死 google/baidu/github/...）**已删**

## 构建 / 测试速查

```bash
swift test                       # 纯 Swift 包（VPNCore/VPNApp/XrayConfig...），编不到 appex
cd Apps && xcodegen generate     # 改了 project.yml / 加删源文件后重新生成工程
open Apps/Qingzhou.xcodeproj          # ⌘R 跑 Qingzhou-iOS（真机）或 Qingzhou-macOS
```
