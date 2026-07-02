# 隧道热切换开关动画 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VPN 开启状态下切换节点/代理模式时，开关跟随真实隧道状态做关→开动画，状态文字变"切换中…"，失败时开关诚实地留在关位。

**Architecture:** `AppState`（`@MainActor @Observable`）新增 `isSwitchingTunnel` 显示标志 + `pendingReapply` 防抖标志；`reapplyRunningTunnel()` 在真实 stop→start 窗口内置位/清位；UI 三处（`vpnRunningBinding` get、HomeView 状态胶囊、macOS StatusBarMenu）消费该标志。不翻转 `isVPNRunning`（它承载"用户意图"语义，被入口 guard 和 NetworkInfoService 依赖）。

**Tech Stack:** Swift 6 / SwiftUI / Observation，XCTest（`swift test`），XcodeGen 工程仅用于最终真跑验证。

**Spec:** `docs/superpowers/specs/2026-07-02-tunnel-switch-toggle-animation-design.md`

## Global Constraints

- 所有改动都在 SPM 包 `Sources/QingzhouApp/` 内，`swift test` 可编译；不改 `Apps/project.yml`、不改 appex 代码。
- `AppState` 是 `@MainActor`，新状态标志的读写天然在主线程，不需要锁。
- `VPNTunnelManager` 是 `final` 具体类（直接调 NetworkExtension 真 API），单测**不可能** mock 隧道启停 —— 单测只覆盖显示逻辑，重启时序靠 macOS 真跑验证（Task 5）。
- 状态文字固定用："切换中…"（跟现有"VPN 已连接"/"VPN 未连接"并列）。
- 提交信息末尾带：
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q53TM5G5zYNNpmeP73BZ33`

---

### Task 1: AppState — `isSwitchingTunnel` 标志 + Toggle 显示逻辑（TDD）

**Files:**
- Modify: `Sources/QingzhouApp/AppState.swift`（属性区 ~line 36-40；`vpnRunningBinding` ~line 270-283）
- Test: `Tests/QingzhouAppTests/AppStateTests.swift`

**Interfaces:**
- Consumes: 现有 `public var isVPNRunning: Bool`、`public var vpnRunningBinding: Binding<Bool>`。
- Produces: `public internal(set) var isSwitchingTunnel: Bool`（默认 `false`；`internal(set)` 让 `@testable` 测试可写，包外只读）。`vpnRunningBinding.wrappedValue == isVPNRunning && !isSwitchingTunnel`。Task 2/3/4 依赖这两者。

- [ ] **Step 1: 写失败测试**

在 `Tests/QingzhouAppTests/AppStateTests.swift` 的 `AppStateTests` 类内追加（文件已有 `@testable import QingzhouApp` 和 `makeState()` helper，直接用）：

```swift
    // MARK: - 隧道热切换的开关显示

    func testSwitchingTunnelDefaultsFalse() {
        let state = makeState()
        XCTAssertFalse(state.isSwitchingTunnel)
    }

    func testVPNToggleShowsOffWhileSwitching() {
        let state = makeState()
        state.isVPNRunning = true
        XCTAssertTrue(state.vpnRunningBinding.wrappedValue)

        // 热切换窗口内：开关显示"关"（真实隧道确实断着）
        state.isSwitchingTunnel = true
        XCTAssertFalse(state.vpnRunningBinding.wrappedValue)

        // 切换结束：滑回"开"
        state.isSwitchingTunnel = false
        XCTAssertTrue(state.vpnRunningBinding.wrappedValue)
    }

    func testVPNToggleStaysOffWhenNotRunningRegardlessOfSwitching() {
        let state = makeState()
        state.isVPNRunning = false
        state.isSwitchingTunnel = true
        XCTAssertFalse(state.vpnRunningBinding.wrappedValue)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter AppStateTests 2>&1 | tail -20`
Expected: **编译失败**，`value of type 'AppState' has no member 'isSwitchingTunnel'`（编译失败即"测试失败"的等价物）。

- [ ] **Step 3: 最小实现**

`Sources/QingzhouApp/AppState.swift` 属性区，在 `isVPNRunning`（line 36）之后插入：

```swift
    /// 热切换窗口标志：VPN 运行中切节点/模式触发全量重启（stop→start）期间为 true。
    /// UI 用它把开关滑到"关"、显示"切换中…"——跟真实断流窗口一致，不做假动画。
    /// 不翻转 isVPNRunning：那个承载"用户意图上 VPN 是开的"，被 reapply 入口 guard
    /// 和 NetworkInfoService（公网 IP 写哪栏）依赖。internal(set) 供 @testable 测试写入。
    public internal(set) var isSwitchingTunnel: Bool = false
```

`vpnRunningBinding`（~line 270）的 get 改为：

```swift
    /// 给 UI Toggle 用的 Binding：set 时异步启停 tunnel，并把 isVPNRunning 同步成实际状态。
    /// get 在热切换窗口内返回 false —— 开关跟真实隧道状态走（切换期间确实断着）。
    public var vpnRunningBinding: Binding<Bool> {
        Binding(
            get: { self.isVPNRunning && !self.isSwitchingTunnel },
            set: { newValue in
                Task { @MainActor in
                    if newValue {
                        await self.startTunnel()
                    } else {
                        await self.stopTunnel()
                    }
                }
            }
        )
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter AppStateTests 2>&1 | tail -5`
Expected: `Test Suite 'AppStateTests' passed`，0 failures。

- [ ] **Step 5: Commit**

```bash
git add Sources/QingzhouApp/AppState.swift Tests/QingzhouAppTests/AppStateTests.swift
git commit -m "AppState: isSwitchingTunnel 标志，热切换期间开关显示为关"
```

---

### Task 2: AppState — reapplyRunningTunnel 置位/清位 + 失败路径 + pendingReapply 防抖

**Files:**
- Modify: `Sources/QingzhouApp/AppState.swift`（`reapplyRunningTunnel()` ~line 358-400；私有属性区 ~line 62-70）

**Interfaces:**
- Consumes: Task 1 的 `isSwitchingTunnel`；现有 `tunnelManager.configure/stop/start/setOnDemandEnabled/status`、`NodeEncoder.shareLink`。
- Produces: `reapplyRunningTunnel()` 外部签名不变（`select()`、`setProxyMode()`、自动择优的调用点零改动）。新私有属性 `pendingReapply: Bool` 和私有方法 `performReapply() async`。

单测说明：`performReapply` 会真调 `NETunnelProviderManager.loadAllFromPreferences`，在 SPM 测试进程里行为未定义（无 entitlement），**不为它写单测**——防抖/失败路径的正确性靠代码评审 + Task 5 真跑验证。本 task 的验证是全量回归 + 编译。

- [ ] **Step 1: 实现**

私有属性区（`private var ipRefreshTask` 之后，~line 66）插入：

```swift
    /// 热切换进行中又来了新的切换请求（快速连点节点）：记 pending，当前轮收尾后再跑一轮。
    /// 不并发跑两个 reapply —— stop/start 交错会打架。
    private var pendingReapply = false
```

把整个 `reapplyRunningTunnel()`（连同它头上的文档注释，line 358-400）替换为：

```swift
    /// 当前节点变了、且 VPN 正在运行时，热切换到新节点：重新写配置 + 断开重连。
    /// 这样自动择优 / 手动选节点能立即生效，不用用户手动关开 VPN 开关。
    ///
    /// 注：NetworkExtension 没有「热 reload 配置」的同步 API —— 改了 providerConfiguration
    /// 必须断开重连才生效。所以这里是 stop → 等连接断开 → start，会有短暂断流；
    /// 期间 isSwitchingTunnel = true，UI 开关滑到关 + 显示"切换中…"。
    ///
    /// 防抖：切换进行中再次调用只记 pending；当前轮收尾后发现 pending 就再跑一轮，
    /// 状态里已是最新节点/模式，自动收敛到用户的最终选择。
    public func reapplyRunningTunnel() async {
        if isSwitchingTunnel {
            pendingReapply = true
            return
        }
        repeat {
            pendingReapply = false
            await performReapply()
        } while pendingReapply
    }

    private func performReapply() async {
        guard isVPNRunning,
              let node = currentNode,
              let shareLink = NodeEncoder.shareLink(node) else { return }
        isSwitchingTunnel = true
        defer { isSwitchingTunnel = false }
        // ⚠️ 原地无感重配（reconfigureInPlace + 扩展 handleAppMessage）暂时禁用 —— 实测在
        // 某些切换（规则→全局）上会让 xray 卡死、之后连全量重启都救不回来，疑似 xray-core
        // 在同一扩展进程内 stop→run 有全局状态没干净复位。扩展侧代码保留待查，这里先走全量重启。
        do {
            try await tunnelManager.configure(
                node: node,
                mode: settings.proxyMode,
                shareLink: shareLink,
                description: "轻舟 · \(node.name)"
            )
            tunnelManager.stop()
            // 等扩展进程**完全断开**再重启 —— 只 sleep 300ms 常常旧进程还没退，start() 复用了
            // 半死的旧进程，xray 在里面 stop→run 状态不干净就会卡死/不通。轮询到 .disconnected
            // （最多 5 秒）确保拿到全新扩展进程（全新 Go runtime + 全新 xray），像首次连接一样干净。
            for _ in 0..<50 {
                if tunnelManager.status == .disconnected { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try await tunnelManager.start()
            logger.info("Clean-restart switched tunnel to \(node.name) / \(settings.proxyMode.rawValue)", category: "tunnel")
        } catch {
            tunnelError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            logger.error("Hot-switch failed: \(tunnelError ?? "?")", category: "tunnel")
            // 隧道确实死了：开关诚实地留在关位（修掉旧行为——失败后开关仍显示"开"）。
            // 和 startTunnel 的失败路径一样干净收尾：关 On-Demand 防止拿坏配置反复重连，
            // 再 stop() 让系统回收 TUN / 路由。pending 也作废——VPN 已关，等用户重新开。
            isVPNRunning = false
            pendingReapply = false
            try? await tunnelManager.setOnDemandEnabled(false)
            tunnelManager.stop()
        }
    }
```

（原实现里被注释掉的 reconfigureInPlace 调用块可一并删除——注释第一行已保留其存在原因和恢复线索。）

- [ ] **Step 2: 全量回归**

Run: `swift test 2>&1 | tail -5`
Expected: 全部通过（147+3 个），0 failures。

- [ ] **Step 3: Commit**

```bash
git add Sources/QingzhouApp/AppState.swift
git commit -m "AppState: 热切换窗口置位 isSwitchingTunnel + 失败留关位 + pendingReapply 防抖"
```

---

### Task 3: HomeView — 状态胶囊"切换中…" + Toggle 禁用 + 平滑动画

**Files:**
- Modify: `Sources/QingzhouApp/HomeView.swift`（`vpnSwitchCard` ~line 53-94）

**Interfaces:**
- Consumes: Task 1 的 `state.isSwitchingTunnel`、改过 get 的 `state.vpnRunningBinding`。
- Produces: 无（纯视图）。

- [ ] **Step 1: 实现**

把 `vpnSwitchCard` 里状态圆圈 + 文字 + Toggle 的 `HStack`（line 55-78）替换为：

```swift
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(circleFill)
                        .frame(width: 56, height: 56)
                    Image(systemName: statusIcon)
                        .font(.title)
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.title3.bold())
                    if let n = state.currentNode {
                        Text("\(n.name) · \(n.protocolType.rawValue.uppercased())")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("未选择节点").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: state.vpnRunningBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    // 热切换窗口内禁点：重启中途再启停会和 stop→start 时序打架
                    .disabled(state.isSwitchingTunnel)
            }
            // 开关滑动 / 图标变色跟着状态平滑过渡，而不是跳变
            .animation(.spring(duration: 0.35), value: state.isVPNRunning)
            .animation(.spring(duration: 0.35), value: state.isSwitchingTunnel)
```

在 `vpnSwitchCard` 定义之后（`}` 与下一个成员之间）加计算属性：

```swift
    // 状态胶囊三态：切换中（橙）> 已连接（绿）> 未连接（灰）
    private var statusText: String {
        state.isSwitchingTunnel ? "切换中…" : (state.isVPNRunning ? "VPN 已连接" : "VPN 未连接")
    }
    private var statusIcon: String {
        state.isSwitchingTunnel ? "arrow.triangle.2.circlepath"
            : (state.isVPNRunning ? "bolt.fill" : "bolt.slash.fill")
    }
    private var statusColor: Color {
        state.isSwitchingTunnel ? .orange : (state.isVPNRunning ? .green : .secondary)
    }
    private var circleFill: Color {
        state.isSwitchingTunnel ? Color.orange.opacity(0.18)
            : (state.isVPNRunning ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
    }
```

注意：`HomeView.swift` 已 `import SwiftUI`，`Color` 直接可用。

- [ ] **Step 2: 编译回归**

Run: `swift build 2>&1 | tail -3 && swift test --filter AppStateTests 2>&1 | tail -3`
Expected: `Build complete!`；AppStateTests 全过。

- [ ] **Step 3: Commit**

```bash
git add Sources/QingzhouApp/HomeView.swift
git commit -m "HomeView: 热切换显示切换中…，开关禁点 + 平滑动画"
```

---

### Task 4: StatusBarMenu（macOS）—"切换中…" + 禁用

**Files:**
- Modify: `Sources/QingzhouApp/StatusBarMenu.swift:12`

**Interfaces:**
- Consumes: 同 Task 3。
- Produces: 无。

- [ ] **Step 1: 实现**

line 12 的 Toggle 替换为：

```swift
        Toggle(
            state.isSwitchingTunnel ? "切换中…" : (state.isVPNRunning ? "VPN 已连接" : "VPN 未连接"),
            isOn: state.vpnRunningBinding
        )
        .disabled(state.isSwitchingTunnel)
```

（菜单栏 Toggle 是 checkbox 形态，系统不做滑动动画，文案 + 勾选态跟真实状态走即可。）

- [ ] **Step 2: 编译回归**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`（StatusBarMenu 在 `#if os(macOS)` 内，本机 macOS 构建能覆盖到）。

- [ ] **Step 3: Commit**

```bash
git add Sources/QingzhouApp/StatusBarMenu.swift
git commit -m "StatusBarMenu: 热切换显示切换中…并禁点开关"
```

---

### Task 5: macOS 真跑验证

**Files:** 无代码改动。构建产物装 `/Applications`。

**Interfaces:**
- Consumes: Task 1-4 全部落地。
- Produces: 行为验证结论（用户肉眼确认）。

- [ ] **Step 1: 全量测试 + macOS App 构建**

```bash
swift test 2>&1 | tail -3
cd Apps && xcodebuild -project Qingzhou.xcodeproj -scheme Qingzhou-macOS -configuration Debug build 2>&1 | tail -5
```

Expected: 测试全过；`** BUILD SUCCEEDED **`。

- [ ] **Step 2: 装到 /Applications 并启动**

```bash
BUILT=$(cd Apps && xcodebuild -project Qingzhou.xcodeproj -scheme Qingzhou-macOS -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')
rm -rf /Applications/Qingzhou.app && cp -R "$BUILT/Qingzhou.app" /Applications/
open /Applications/Qingzhou.app
```

- [ ] **Step 3: 请用户肉眼确认（唯一需要用户的环节——动画效果只有人能判断）**

VPN 开启状态下：
1. 首页切代理模式（分段控件）→ 开关滑到关、胶囊变橙色"切换中…"，几秒后滑回开、恢复"VPN 已连接"；
2. 节点列表切节点 → 同样表现；
3. 切换进行中快速连点两个节点 → 不报错，最终连到最后点的那个；
4. 状态栏菜单在切换期间显示"切换中…"且开关灰置。

确认无误后本 feature 完成（走 finishing-a-development-branch 流程决定合并方式）。
