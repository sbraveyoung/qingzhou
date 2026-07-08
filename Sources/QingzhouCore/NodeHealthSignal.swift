import Foundation

/// 隧道扩展 → 主 App 的「节点健康」信号（App Group `node-health.json`）。
///
/// 扩展里 `NodeHealthDetector` 确认 `.suspect` 时写一条；主 App 轮询读出、判新鲜后
/// 决定是否显示「当前节点疑似故障」横幅 + 一键切。**只吐瞬时结论，不留 history**
/// （历史留主 App，扩展 50MB 内存预算下不背历史，见 docs/FAILOVER.md）。
public struct NodeHealthSignal: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case healthy
        case suspect
    }

    /// 当前判定。
    public var state: State
    /// 判定针对的节点名（主 App 一键切时用来**排除**这个疑似节点）。
    public var nodeName: String
    /// 判定/写入时刻（ISO8601 编码，与 AppGroupStorage 解码策略一致）。主 App 用它判新鲜。
    public var at: Date

    public init(state: State, nodeName: String, at: Date) {
        self.state = state
        self.nodeName = nodeName
        self.at = at
    }

    /// 由纯逻辑判定结果构造。
    public init(_ health: NodeHealth, nodeName: String, at: Date) {
        self.state = (health == .suspect) ? .suspect : .healthy
        self.nodeName = nodeName
        self.at = at
    }
}
