# 隧道热切换的开关动画反馈 — 设计

日期：2026-07-02

## 背景 / 问题

VPN 开启状态下切换节点或代理模式时，`AppState.reapplyRunningTunnel()`
（`Sources/QingzhouApp/AppState.swift`）会做真·全量重启：configure → stop →
轮询到 `.disconnected`（最长 5 秒）→ start。期间隧道实际断开，但 `isVPNRunning`
全程保持 `true`，首页开关、状态胶囊（"VPN 已连接" + 闪电图标）和 macOS
状态栏 Toggle 毫无反应——用户感知不到切换在发生，也不知道短暂断流是正常的。

## 目标

切换期间给出诚实的视觉反馈：开关带动画滑到关、状态文字变"切换中…"，
隧道重新连上后开关滑回开、文字恢复。动画时长 = 真实重启时长（约 0.5~5 秒），
不做固定节奏的演出动画。

## 设计

### 状态模型（AppState）

新增独立标志，不翻转真实的 `isVPNRunning`：

```swift
public private(set) var isSwitchingTunnel = false
```

- `isVPNRunning` 语义保持"用户意图上 VPN 是开的"，它还被
  `reapplyRunningTunnel` 入口 guard、`vpnRunningBinding`、
  `NetworkInfoService`（公网 IP 写"代理"还是"直连"栏）依赖，中途翻转会连锁误判。
- `reapplyRunningTunnel()` 通过 guard 后置 `isSwitchingTunnel = true`；
  `start()` 成功后置回 `false`。
- **失败路径**：start 抛错 → `isSwitchingTunnel = false` 且
  `isVPNRunning = false`（隧道确实死了，开关留在关位），`tunnelError` 照旧弹
  alert。顺带修掉现存问题：热切换失败后开关仍显示"开"。

### 防抖 / 重入

切换进行中用户又选了另一个节点：不并发跑第二个 `reapply`（现状 stop/start
会交错打架），改为 `pendingReapply` 标志——当前这轮跑完发现有 pending 就再跑
一轮。状态里已是最新节点/模式，自动收敛到用户的最终选择。

### UI（3 处，全在 QingzhouApp 包）

1. `vpnRunningBinding` 的 get 改为 `isVPNRunning && !isSwitchingTunnel`
   —— HomeView 与 StatusBarMenu 两个 Toggle 一处改动全覆盖。
2. **HomeView**：
   - 状态胶囊：切换中显示"切换中…"，图标用橙色 `arrow.triangle.2.circlepath`；
   - Toggle 加 `.disabled(state.isSwitchingTunnel)` 防误触；
   - 加 `.animation(.spring(duration: 0.35), value: …)` 让开关滑动平滑。
3. **StatusBarMenu（macOS）**：Toggle 文案加"切换中…"分支 + 同样 disabled。

## 测试 / 验证

- `tunnelManager` 是具体类（包 `NETunnelProviderManager`），SPM 单测覆盖不到
  真实启停；`swift test` 保证编译 + 现有测试不回归。
- 行为验证：build 并运行 Qingzhou-macOS，VPN 开启时切节点/切模式，肉眼确认
  开关关→开动画、"切换中…"文字、失败时开关留在关位。
