# 测试报告

> 阶段 1.5+ 测试执行结果。下一阶段会扩充集成测试（接入真 sing-box 核心后）和 UI 自动化测试。

## 环境

| 项目 | 值 |
|---|---|
| 仓库版本 | 阶段 1.5+ |
| 执行日期 | 2026-05-12 |
| 系统 | macOS Darwin 25.4.0 (x86_64) |
| Swift | 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102) |
| Xcode | 26.4.1 (17E202) |
| 测试框架 | XCTest |
| 命令 | `swift test` |

## 总览

| 指标 | 数值 |
|---|---|
| 通过 | 113 |
| 失败 | 0 |
| 异常退出 | 0 |
| 测试耗时 | 1.35s（pure），1.38s（含 setup/teardown） |
| 测试模块 | 7（每个 Source 模块一一对应） |

```
Executed 113 tests, with 0 failures (0 unexpected) in 1.351 (1.377) seconds
```

## 按模块拆分

| 模块 | 测试数 | 失败 | 耗时 | 覆盖点 |
|---|---:|---:|---:|---|
| `VPNCoreTests` | 16 | 0 | 0.020s | 协议枚举、节点排序、订阅使用率、规则源文本、连接活跃判断、字节格式化、**Settings JSON 旧版本兼容性 (4)** |
| `VPNLoggingTests` | 8 | 0 | 0.010s | 级别比较、环形缓冲淘汰、关键字 / 级别搜索、订阅回调、文件落盘 |
| `VPNProtocolsTests` | 28 | 0 | 0.095s | trojan / ss / vmess / vless / hy2 全部成功 + 错误路径；**Clash YAML 解析 (13)**：检测、proxy-providers、各协议字段映射、未知 type 静默跳过、缺失字段错误收集、port 既支持数字又支持字符串 |
| `VPNRulesTests` | 24 | 0 | 0.017s | IPv4 / IPv6 CIDR 解析与命中、所有规则类型解析、引擎匹配优先级、未命中兜底、关键字 / 类型搜索 |
| `VPNSpeedTestTests` | 5 | 0 | 0.004s | 内置目标 URL 完整性、并发探针顺序保持、节点延迟排名、排除节点跳过、全失败时返回 nil |
| `VPNSubscriptionTests` | 9 | 0 | 0.008s | base64 / 明文 / 无 padding 三种订阅体；userinfo header 完整 / 部分 / 含无效字段；fetcher 写回订阅元数据 |
| `VPNAppTests` | 23 | 0 | 1.18s | 持久化 round-trip / 损坏文件恢复；远程规则拉取 + 错误传播；QR 生成；AppState 节点去重 / 批量添加 / 排除清空 / 订阅删除级联 / 自定义规则优先 / 调度器启停；**Locale 解析器 (4)** |

## 重点新增测试 (阶段 1.5+)

### Clash YAML 解析 (13)
- `testDetectClashConfig` / `testDetectClashProviders` / `testDoesNotMatchPlainLinks`
- `testParseTrojan` / `testParseShadowsocks` / `testParseVMess` / `testParseVLESS` / `testParseHysteria2`
- `testParseUnsupportedTypeSkippedSilently`
- `testParseInvalidEntryCollectsError`
- `testParseRejectsNonClash`
- `testParseProviderInlinePayload`
- `testPortAsStringStillParses`

### Settings JSON 迁移 (4)
- `testDecodeEmptyJSONUsesDefaults`
- `testDecodeOldSnapshotWithoutNewFields`：模拟阶段 1.5 之前的 `state.json`（无 `subscriptionRefreshIntervalSeconds`），解码不报错且新字段使用默认值
- `testRoundtripPreservesNewField`
- `testZeroIntervalMeansOff`

### Locale 解析 (4)
- `testSystemUsesAutoupdatingCurrent`
- `testFixedLanguagesMapToCorrectIdentifiers`
- `testJaLocaleFormatsDatesInJapanese`：验证 ja Locale 渲染日期包含「月」
- `testEnLocaleFormatsDatesInEnglish`：验证 en Locale 渲染包含英文月名

## 跨平台编译验证

| 目标 | 命令 | 结果 |
|---|---|---|
| macOS 14 (x86_64) lib | `swift build` | ✅ BUILD COMPLETE |
| iOS 17 (arm64) lib | `xcodebuild -scheme VPN-Package -destination 'generic/platform=iOS'` | ✅ BUILD SUCCEEDED |
| macOS App | `xcodebuild -scheme VPN-macOS` (XcodeGen-generated) | ✅ BUILD SUCCEEDED |
| iOS Simulator App | `xcodebuild -scheme VPN-iOS -destination 'iOS Simulator'` | ✅ BUILD SUCCEEDED |
| macOS App 实际启动 | `open VPN-macOS.app` | ✅ 进程起来，无 crash |
| 持久化目录 | `~/Library/Application Support/VPN/` | ✅ 自动创建 |

## 已知未覆盖的部分

下面这些**不在阶段 1.5+ 范围**，未写测试 —— 阶段 2 引入后会补：

| 区域 | 原因 |
|---|---|
| `PacketTunnelProvider` 行为 | 还没引入 Network Extension target |
| 通过代理的端到端速度 | 需要 PacketTunnel 实际运行 |
| 真实连接列表 | 当前是 sampleConnectionsLoop 生成的演示数据 |
| SwiftUI 视图渲染 | 阶段 3 用 XCUITest 做 |
| UI 字符串完整翻译 | Locale 切换已工作，但 `Localizable.xcstrings` 尚未提供 —— 社区贡献入口已就绪 |
| 真实 GEOIP 数据库 | `GeoIPResolver` 是 protocol，注入实现后再加 |
| `NetworkInfoService` 真出网 | 单测用 mock 避免不稳定 |
| macOS `MacSystemServices` `networksetup` 真调用 | 涉及系统配置改动；需 sandbox 关闭 + 手动验证 |

## 复现步骤

```bash
git clone <repo>
cd vpn
swift test                    # → Executed 113 tests, with 0 failures
cd Apps && xcodegen generate
xcodebuild -project VPN.xcodeproj -scheme VPN-macOS \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -project VPN.xcodeproj -scheme VPN-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

预期输出：`Executed 113 tests, with 0 failures` 和三次 `** BUILD SUCCEEDED **`。
