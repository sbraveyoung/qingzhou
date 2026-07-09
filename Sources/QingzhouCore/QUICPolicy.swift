import Foundation

/// QUIC（UDP 443 / HTTP/3）阻断策略。三档，取代 build 10 的 `blockQUIC: Bool` 单开关。
/// 语义与「非对称探测」的取舍见 docs/QUIC.md。
/// - auto（默认）：非对称——hysteria2（QUIC 原生协议节点）先**放行**并连接后实测 h3，
///   实测走不通再挡；其余 TCP 基协议直接挡（它们 UDP 转发普遍差，探测只是徒增一跳成本）。
/// - alwaysBlock（强制开启阻断）：所有节点、所有情况恒挡 UDP 443 → 强制回退 TCP。
/// - neverBlock（强制关闭阻断）：所有节点恒放行 QUIC（UDP 转发能力好的自建节点用）。
public enum QUICPolicy: String, Codable, Sendable, CaseIterable {
    case auto
    case alwaysBlock
    case neverBlock
}

/// QUIC 策略 → 「当前节点是否应阻断 UDP 443」的**纯逻辑**（无 IO，全分支可测）。
/// 由主 App 在每个 compose 调用点算出有效 bool，经 providerConfiguration 传给扩展 ——
/// 扩展侧 routing 仍只吃一个 `blockQUIC: Bool`（键名不变），三档语义全在这里收敛。
public enum QUICPolicyResolver {
    /// - Parameters:
    ///   - policy: 用户选的三档策略。
    ///   - protocolType: 当前节点协议。只有 hysteria2 在 auto 下享受「先放行」待遇。
    ///   - knownBrokenOnThisNode: 该节点是否已被本会话的 HTTP/3 实测判定「QUIC 走不通」。
    /// - Returns: true = 阻断 UDP 443（reject → 回退 TCP）；false = 放行 QUIC。
    public static func shouldBlock(
        policy: QUICPolicy,
        protocolType: ProxyProtocol,
        knownBrokenOnThisNode: Bool
    ) -> Bool {
        switch policy {
        case .alwaysBlock:
            return true
        case .neverBlock:
            return false
        case .auto:
            // hysteria2：QUIC 原生协议，默认相信它能转发 UDP → 放行；只有实测坏才挡。
            if protocolType == .hysteria2 {
                return knownBrokenOnThisNode
            }
            // 其余协议（trojan / vmess / vless / shadowsocks）：UDP 转发普遍差，直接挡。
            return true
        }
    }
}

/// HTTP/3 实测探测的**决策纯逻辑**：拿到「实际协商到的传输协议名」后，判断是否要把
/// 该节点标记为「QUIC 实测坏」。URLSession 调用本身在 App 层（靠编译 + 真机），这里只做判定。
public enum QUICProbeDecision {
    /// - Parameter networkProtocolName: `URLSessionTaskMetrics.transactionMetrics.last?.networkProtocolName`
    ///   —— 走上 HTTP/3 时是 `"h3"`；回退 HTTP/2 / HTTP/1.1 时是 `"h2"` / `"http/1.1"`；
    ///   请求整体失败 / 拿不到 metrics 时为 nil。
    /// - Returns: true = 标记该节点 QUIC 实测坏（该挡）；false = h3 真能跑，保持放行。
    public static func shouldMarkBroken(networkProtocolName: String?) -> Bool {
        // 只有明确协商到 h3 才算 QUIC 可用；其余（回退协议 / nil）一律判坏，保守回退 TCP。
        networkProtocolName != "h3"
    }
}
