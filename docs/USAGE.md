# 使用方法

## 作为库使用（最快上手）

```swift
import VPNCore
import VPNProtocols
import VPNSubscription
import VPNRules
import VPNSpeedTest
import VPNLogging

// 1. 解析单个节点链接
let node = try ProxyURLParser.parse("trojan://pw@example.com:443#HK")
print(node.host, node.port, node.protocolType)

// 2. 解析订阅响应体
let body = """
trojan://pw@a.com:443#A
ss://YWVzLTEyOC1nY206cHc=@b.com:8388#B
"""
let payload = SubscriptionParser.parse(body: body)
print("got \(payload.nodes.count) nodes")

// 3. 拉取订阅（真实网络）
let fetcher = SubscriptionFetcher()
let sub = Subscription(name: "MySub", url: URL(string: "https://x.com/sub")!)
let (updated, refreshed) = try await fetcher.refresh(sub)
print("流量 \(updated.usedBytes ?? 0) / \(updated.totalBytes ?? 0)")

// 4. 规则匹配
let rules = """
DOMAIN-SUFFIX,google.com,PROXY
GEOIP,CN,DIRECT
FINAL,PROXY
"""
let (parsed, _) = RuleParser.parseAll(rules)
let engine = RuleEngine(rules: parsed)
let result = engine.match(MatchContext(host: "mail.google.com"))
print(result.target)   // PROXY

// 5. 测速
let runner = SpeedTestRunner()
let report = await runner.runBuiltInTargets()
for r in report.results {
    print("\(r.url.host ?? ""): \(r.latencyMs.map(String.init) ?? "fail") ms")
}

// 6. 节点自动择优
let selector = NodeSelector()
let measured = await selector.measure(nodes: refreshed.nodes)
let best = await selector.pickBest(from: measured)
print("最优节点：\(best?.name ?? "无")")

// 7. 日志
let logger = Logger(capacity: 5000, minimumLevel: .debug)
logger.info("started", category: "app")
let errors = logger.search(level: .warn, keyword: "")
```

## 作为 App 运行

见 [`../Apps/README.md`](../Apps/README.md)。简版：

1. Xcode 新建 iOS / macOS App 项目；
2. 把本仓库作为 Local Package 加进去；
3. 入口替换为 `VPNiOSApp.swift` / `VPNMacApp.swift` 的内容；
4. ⌘R 跑起来。

跑起来后可以做：

| 想做的事 | 路径 |
|---|---|
| 添加单个节点链接 | 节点页 → 右上「+」→ 粘贴 `trojan://...`（多行批量也行） |
| **粘贴 Clash YAML 配置** | 节点页 → 右上「+」→ 把整段 YAML（含 `proxies:` 段）粘进去 → 添加 |
| iOS 扫码加节点 | 节点页 → 右上「+」→ 添加面板里点「扫码」 |
| **查看 / 编辑节点详情** | 节点页 → 右键节点 → 「查看详情 / 编辑」（或 iOS 上左滑「详情」） |
| 添加订阅 | 订阅页 → 填名称 + URL → 添加并刷新 |
| 刷新所有订阅 | 订阅页 → 每条上的「刷新」；调度器也会每小时自动刷一次 |
| 分享节点 / 订阅二维码 | 节点页右键节点 → 「分享二维码」；订阅页点「分享」 |
| 手动测速所有节点 | 节点页 → 右上「测速」 |
| 自动择优一次 | 节点页 → 右上「择优」 |
| 自动定时择优 | 设置页 → 自动化 → 自动择优时机 |
| **订阅自动刷新间隔** | 设置页 → 自动化 → 订阅自动刷新（关闭 / 15 分 / 30 分 / 1 时 / 6 时 / 24 时） |
| 排除节点 | 节点页 → 在节点上右键 → 「排除节点」 |
| 删除节点 | 节点页 → 右键 → 删除（或 iOS 上左滑） |
| 测试 Bilibili / Google / Claude 等 | 首页 → 网站测试卡 → 开始测试 |
| 查看公网 IP 与 ISP | 首页 → 公网 IP 卡 |
| 切换代理模式 | 首页 → VPN 卡片 → 模式 segmented |
| 修改 HTTP / SOCKS 端口 / 日志级别 | 设置页 → 代理 |
| 主题 / 语言 | 设置页 → 外观（语言切换会立即影响日期 / 数字 / 相对时间的渲染；UI 字符串翻译走 .xcstrings，社区贡献） |
| 终端环境变量 | 设置页 → 底部 shell 片段（一键复制） |
| 修改 / 刷新规则源 | 规则页 / 设置页 → 规则源 URL |
| 添加自定义规则 | 规则页 → 顶部输入 `DOMAIN-SUFFIX,example.com,PROXY` → 添加 |
| 搜索规则 | 规则页 → 顶部 Search（同时搜自定义和远程） |
| 看连接 | 连接页 → 活跃 / 已关闭 / 全部 segment + Search（演示数据自动注入） |
| 看日志 | 日志页 → 级别 segment + 关键字搜索 |
| macOS 状态栏开关 VPN / 切节点 / 切模式 | 屏幕右上角三角图标 |
| macOS 开机自启 | 设置页 → macOS 集成 → 开机自启 + 「立即应用」 |
| macOS 设置系统代理 | 设置页 → macOS 集成 → 启用系统代理 + 「立即应用」（需 app 不在 sandbox 中） |

## 真要让流量走代理

当前阶段 1 的 App 跑起来后，所有 UI 都能用、订阅能拉、节点能存、规则能匹配、延迟能测，但 **VPN 开关只是个状态位**，不会真的建立隧道。这是有意为之 —— 真隧道部分（Packet Tunnel Provider + sing-box 核心）属于阶段 2，需要：

1. Apple Developer 账号 + Network Extensions entitlement；
2. 一个 Network Extension target；
3. sing-box 编出来的 `xcframework`；
4. App Group 配置。

步骤见 [BUILD.md 第 4–7 节](BUILD.md#启用真正的-vpn-隧道阶段-2-工作)。
