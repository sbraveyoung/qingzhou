import Foundation
import UserNotifications
import QingzhouCore

/// 健康触发的无感故障切换 —— 主 App 侧（保守 MVP：告警 + 一键切，不自动切数据面）。
///
/// 扩展里 `NodeHealthDetector` 判 `.suspect` → 写 App Group `node-health.json` + 发本地通知。
/// 这里：每秒读信号驱动横幅（`syncNodeHealth`）、用户一键 / 通知点击触发 `failoverToBestNode`
/// （排除疑似节点 → 现有打分选最优 → `reapplyRunningTunnel(.nodeOnly)`，复用现有切换路径）。
///
/// 设计边界（docs/FAILOVER.md）：首版**不**自动切、不主动探测、不熔断；用户手动一键天然限速。
extension AppState {

    // MARK: - 读信号

    /// 每秒读扩展写的健康信号，驱动「疑似故障」横幅。任一不满足即收起：特性关 / 用户没
    /// opt-in / VPN 没跑 / 信号非 suspect / 信号过期（>8s，扩展 2s 一写）。
    func syncNodeHealth() {
        guard FeatureFlags.autoFailoverAlert, settings.autoFailoverAlert, isVPNRunning else {
            if nodeHealthSuspect != nil { nodeHealthSuspect = nil }
            return
        }
        // "node-health" 与 XrayCore.TunnelAppGroup.nodeHealthName 一致（两模块互不依赖）。
        if let sig = AppGroupStorage.read(NodeHealthSignal.self, from: "node-health"),
           sig.state == .suspect,
           abs(sig.at.timeIntervalSinceNow) <= 8 {
            if nodeHealthSuspect != sig { nodeHealthSuspect = sig }
        } else if nodeHealthSuspect != nil {
            nodeHealthSuspect = nil
        }
    }

    // MARK: - 一键切换

    /// 一键「切换到最优节点」：排除疑似故障节点，用**现有打分**选最优健康替代，走
    /// `reapplyRunningTunnel(.nodeOnly)`（复用原地换出口快路径，不新造切换路径）。
    ///
    /// failover 是「死了→切」的独立意图，**绕开分数黏性/幅度闸**（那些是「也许更好→别折腾」，
    /// 方向相反，见 docs/FAILOVER.md F22）。故意不重新测速：死节点所在网络测速慢且不可靠，
    /// 用已有打分数据即时切走更稳；扩展换节点后会重建 baseline 从头判。
    public func failoverToBestNode() async {
        guard FeatureFlags.autoFailoverAlert, !nodes.isEmpty else { return }
        let suspectName = nodeHealthSuspect?.nodeName
        // 排除对象：当前节点 + 信号点名的疑似节点（短时不切回，F13 的保守版）。
        let isSuspect: (Node) -> Bool = { node in
            node.id == self.currentNodeId || (suspectName != nil && node.name == suspectName)
        }
        let candidates = nodes.filter { !isSuspect($0) && !isEffectivelyExcluded($0) }
        guard !candidates.isEmpty else {
            // 没有健康替代 → 不无限切，提示机场疑似整体不可用（F10/F12 保守版）。
            showToast(L("暂无可切换的健康节点，机场可能整体不可用"))
            return
        }
        // 有测速数据的走「地区排除 + 地区优先 + NodeScorer 总分」；都没测过则退化取第一个候选。
        let best = pickBestRespectingRegions(from: candidates) ?? candidates.first!
        logger.warn("故障切换：疑似故障节点 → 切到 \(best.name)", category: "app")
        currentNodeId = best.id
        persist()
        nodeHealthSuspect = nil   // 先收起横幅；扩展换节点后重建 baseline 再重新判
        showToast(L("已切换到 \(best.name)"))
        if isVPNRunning {
            await reapplyRunningTunnel(scope: .nodeOnly)
        }
    }

    // MARK: - 通知权限 + 点击回调

    /// 单元测试宿主里没有合法 app bundle，`UNUserNotificationCenter.current()` 会抛
    /// NSException（bundleProxyForCurrentProcess 为 nil）。判据：XCTest 运行时已加载
    /// （XCTestCase 类存在）或没有 bundle id —— 两者任一即跳过所有通知相关调用。
    var notificationsAvailable: Bool {
        NSClassFromString("XCTestCase") == nil && Bundle.main.bundleIdentifier != nil
    }

    /// 用户开「节点故障提醒」时申请通知权限（进程内只申请一次）。未授权时扩展的通知
    /// 静默 no-op —— 这就是 opt-in 的天然闸门（没开开关的用户永不被打扰）。
    func requestFailoverNotificationAuthorizationIfNeeded() {
        guard notificationsAvailable, !didRequestFailoverAuth else { return }
        didRequestFailoverAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                if let error {
                    self?.logger.warn("通知权限申请失败：\(error.localizedDescription)", category: "app")
                } else {
                    self?.logger.info("通知权限：\(granted ? "已授予" : "被拒绝")", category: "app")
                }
            }
        }
    }

    /// 挂 UNUserNotificationCenter delegate（幂等）—— 让「疑似故障」通知在前台也弹、
    /// 点击能触发切换。delegate 是独立 NSObject（@objc 协议要求），由 AppState 强持有。
    func wireFailoverNotificationDelegate() {
        guard notificationsAvailable, !didWireNotificationDelegate else { return }
        didWireNotificationDelegate = true
        let delegate = FailoverNotificationDelegate(state: self)
        failoverNotificationDelegate = delegate   // center.delegate 是 weak，必须强引用
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// 通知点击 → 打开 App 触发同一切换（复用一键切逻辑）。跳到首页让用户看到结果 toast。
    func handleFailoverNotificationTap() async {
        activeSection = .home
        await failoverToBestNode()
    }
}

/// 「疑似故障」通知的点击 / 前台展示回调。@objc 协议要求 NSObject，故独立于 AppState。
/// weak 持有 AppState，回调里跳回主 actor 触发一键切。
final class FailoverNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    weak var state: AppState?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    /// App 前台时也把「疑似故障」通知弹出来（否则用户正在用 App 反而收不到提示）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 用户点了通知（或其动作按钮）→ 触发一键切。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let type = response.notification.request.content.userInfo["type"] as? String
        completionHandler()
        guard type == "nodeHealthSuspect" else { return }
        Task { @MainActor [weak state] in await state?.handleFailoverNotificationTap() }
    }
}
