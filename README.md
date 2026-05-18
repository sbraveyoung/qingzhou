# VPN

一个跨平台（iOS / macOS，Linux 也能跑核心库）的 VPN 客户端，目标对标 Shadowrocket / Clash 类工具。

> **状态：S1 内核集成已完成。** 目标是 W9-10 上 App Store。完整 12-sprint 路线图见 [docs/ROADMAP.md](docs/ROADMAP.md)。
>
> 已完成：
> - **S0** Foundation：订阅 / 节点 / 规则 / UI / 持久化 / QR / IP 信息 / macOS 系统集成（113 测试）
> - **S1** 内核集成：libXray.xcframework（xray-core MIT binding）编通 + Swift 包装层 + 3 项 XrayCore 测试 + macOS app 启动验证（**116 测试全过**）
>
> 下一步：**S2 Tunnel 接通**（NEPacketTunnelProvider ↔ xray-core 双向桥接，真 iPhone 翻墙）。

## 特性

### 协议与订阅
- **协议链接解析**：trojan、ss（SIP002 + legacy + URL-safe base64）、vmess、vless、hysteria2 / hy2。
- **Clash / Mihomo / Stash YAML 导入**：订阅 URL 返回 YAML 自动识别；手动添加面板直接粘贴 YAML 也能解析；支持 `proxies` 和 `proxy-providers` inline `payload` 两种结构。
- **订阅管理**：URL 拉取 + base64 / 明文 / YAML 三种格式自动识别 + `Subscription-Userinfo` 响应头解析（流量、到期时间）；UI 错误展示。
- **订阅自动刷新可配**：关闭 / 15 分钟 / 30 分钟 / 1 小时 / 6 小时 / 24 小时，单独于自动择优间隔。
- **节点详情 / 编辑**：点节点列表右键「查看详情」 → 表单形式编辑所有字段（含参数字典增删改）。
- **QR 分享**：每个节点和订阅都能生成二维码分享。
- **QR 扫码（iOS）**：相机扫码直接添加节点。

### 规则
- **本地规则引擎**：`DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`、`IP-CIDR`、`IP-CIDR6`、`GEOIP`、`PROCESS-NAME`、`USER-AGENT`、`FINAL`；自包含 IPv4/IPv6 CIDR 实现；GEOIP 走可注入接口。
- **远程规则订阅**：拉取默认 [whitelist.conf](https://raw.githubusercontent.com/pexcn/daily/gh-pages/shadowrocket/whitelist.conf) 或任何自定义 URL；自定义规则始终优先。
- **规则页**：按类型 / 关键字搜索，自定义与远程分组展示，目标用色块区分（PROXY 蓝 / DIRECT 绿 / REJECT 红）。

### 节点
- 按名称 / 按延迟排序；排除节点；订阅刷新保留测速结果。
- 内置 9 个测速目标（Bilibili 国内 / 港澳台、Google、Anthropic、ChatGPT、Claude、Gemini、TikTok、YouTube）。
- 自动择优：app 启动 / 定时 / 启动 + 定时三种触发，间隔可配。

### 持久化
- 订阅 / 节点 / 自定义规则 / 设置 / 当前节点 全部以 JSON 落盘，重启不丢。
- 数据目录：`~/Library/Application Support/VPN/`（macOS）或 `Documents/VPN/`（iOS）。
- 原子写入（`.atomic`），中断不会留下半截文件。

### UI
- 跨平台 SwiftUI：首页、节点、订阅、规则、连接、日志、设置。
- 首页卡片：VPN 开关 / 当前节点 / 订阅进度 / 公网 IP（含地理 + ISP）/ 流量统计 / 网站测试 / 系统信息。
- 节点行延迟用红 / 橙 / 绿色块直观区分；空状态有 CTA。
- 日志页按级别 segment + 关键字搜索，级别染色。
- 连接页活跃 / 已关闭 / 全部 segment，每条显示 host / 命中规则 / 走哪个节点 / 流量 / 速率。
- macOS 状态栏 MenuBarExtra：VPN 开关、当前节点 + 延迟、节点切换、模式切换、订阅刷新、一键择优、刷新规则、退出。

### 设置
- 代理模式、HTTP / SOCKS 端口、日志级别。
- 自动择优时机 / 间隔；订阅自动刷新间隔单独可配。
- 主题（深 / 浅 / 跟随系统）、语言（zh-Hans / zh-Hant / en / ja）—— 通过 `Locale` 环境立即影响 SwiftUI 的日期 / 数字 / 相对时间渲染。
- 终端环境变量片段（bash / zsh / fish / powershell），一键复制。
- macOS 专属：**开机自启**（`SMAppService`）+ **系统代理**（`networksetup`）。
- 设置变更通过统一的 `setting(\.X)` Binding 自动 persist + 同步副作用（如 logger 级别）。
- Settings JSON 解码做了字段兼容（新加字段不会让旧用户的存档失效）。

### 其他
- 公网 IP / 地理 / ISP 查询（ipapi.co）。
- 完整 92 项单测覆盖所有逻辑分支。

## 快速上手

```bash
git clone https://github.com/<你的用户名>/vpn.git
cd vpn
swift build                  # 编译所有库
swift test                   # 跑 73 项单测

# 跑 iOS / macOS App：
brew install xcodegen        # 一次性
cd Apps && xcodegen generate
open VPN.xcodeproj           # 在 Xcode 里选 VPN-iOS / VPN-macOS scheme，⌘R
```

真机调试、Bundle ID、签名等详见 [Apps/README.md](Apps/README.md)。

## 仓库结构

```
Package.swift                # SPM 入口，定义 7 个库 + 7 个测试 target
Sources/
  VPNCore/         # 协议无关的领域模型：Node / Subscription / Rule / Connection / Settings
  VPNProtocols/    # 协议链接解析：trojan / ss / vmess / vless / hy2
  VPNSubscription/ # 订阅获取 + 解析 + userinfo header
  VPNRules/        # 规则解析 + CIDR + 匹配引擎
  VPNSpeedTest/    # 测速 target + 探针 + 节点择优
  VPNLogging/      # 分级日志 + 环形缓冲 + 文件落盘
  VPNApp/          # SwiftUI 视图层 + AppState + 持久化 + 远程规则 + IP 信息 + QR + macOS 服务
Tests/             # 各模块单测，共 92 项
Apps/              # iOS / macOS app（XcodeGen 生成 .xcodeproj）
docs/              # 详细文档
```

## 文档

- [使用方法](docs/USAGE.md)
- [架构总览](docs/ARCHITECTURE.md)
- [构建说明](docs/BUILD.md)
- [测试报告](docs/TEST_REPORT.md)
- [贡献指南](docs/CONTRIBUTING.md)

## 路线图

- **阶段 1（已完成）**：核心库 + UI 骨架 + 单测。
- **阶段 1.5（已完成）**：持久化、远程规则、定时器、QR 扫码 / 分享、macOS 系统集成、UI 打磨、IP 信息。
- **阶段 2**：集成 sing-box xcframework；Network Extension Target；端到端真实代理；
  连接级数据上报；iOS / macOS Widget；状态栏一键开关 VPN（接通真隧道）。
- **阶段 3**：自定义规则可视化编辑、Mihomo / Clash YAML 配置导入、iCloud 同步、UI 国际化资源、XCUITest。

## 协议

MIT。详见 [LICENSE](LICENSE)。
