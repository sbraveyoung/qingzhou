import Foundation

/// 节点健康判定的**输出**：只有两态，绝不越权做「切换决策」。
///
/// `.suspect` = 「配对判据（上行还在涨、下行却持平）持续到阈值」的**观测结论**，
/// 不等于「一定死了」——它是给用户告警 + 一键切的触发信号，不做静默自动切数据面
/// （首版保守 MVP，见 docs/FAILOVER.md）。
public enum NodeHealth: Sendable, Equatable {
    /// 健康 / 无法判定（空闲、direct 无上行、判定空窗内 …）—— 一律按 healthy 对外。
    case healthy
    /// 疑似故障：上行在涨、下行却持平，且已持续到阈值。
    case suspect
}

/// 「节点疑似故障」的**纯逻辑**判定器（无 IO / 无 UI / 无时钟依赖，全部时间由调用方喂）。
///
/// 数据源只用 xray proxy per-outbound 累计计数（`reportXrayOutboundStats`，≈2s 一采）。
/// 判据 =「**上行还在涨、下行却持平**，持续 ≥ suspectSustainSeconds」——这是唯一能把
/// 「节点死了但 app 还在重试发包」和「用户只是没上网」区分开的被动信号。
///
/// 设计要点（每条对应 docs/FAILOVER.md 红队失败模式 F#）：
/// - **配对判据**（F4/F19）：只有「上行速率 ≥ 活跃门 且 下行速率 < 持平门」才算「坏窗」；
///   任一不满足即非坏窗。空闲（上行也不动）→ healthy；下行有回流 → healthy。
/// - **持续 + 去抖迟滞**（F3）：坏窗必须**连续**满 `suspectSustainSeconds` 才判 suspect；
///   进入门槛这么高，天然抗单窗抖动。恢复对称：一旦出现「下行真回流」就清 suspect，
///   而**再次**进入 suspect 又要重新走满整段持续 → 不会快速抖动。
/// - **baseline 重置**（F5）：`resetBaseline()`（switch/restart 后调）作废旧 baseline，
///   下一条样本重建 baseline 并重新起 grace（判定空窗），旧累计一律作废。
/// - **起手宽限**（F7）：建链 / 切换后 `graceSeconds` 内不判（连接刚起、握手期本就抖）。
/// - **睡眠跳变**（F8）：样本间隔 > `maxSampleGapSeconds`（挂起/时钟跳变）→ 丢弃该窗、
///   重建 baseline + 重新宽限。计数器回退（xray 重启归零）同样处理。
/// - **模式感知**（F19 变体）：proxy 无上行（direct / 规则全直连）→ 落进「空闲」分支 → no-op。
///
/// **值类型**：扩展里每个采样点 `ingest(...)`；**不留 history**（历史留主 App）。
public struct NodeHealthDetector: Sendable {

    // MARK: - 阈值常量（都可调；soak 后按误报率再收紧/放宽）

    /// 「坏窗」必须**连续**成立多少秒才判 suspect。docs/FAILOVER.md 建议 8~12s，取 10s：
    /// 短于此易被慢源站 TTFB / 单次重传误报，长于此告警太迟钝。
    public static let suspectSustainSeconds: TimeInterval = 10

    /// 建链 / 切换后的判定空窗（秒）。连接刚起、TLS 握手期上行可能领先下行一小会儿，
    /// 这段不判。也是 resetBaseline / 睡眠重建 后的冷启动缓冲。
    public static let graceSeconds: TimeInterval = 6

    /// 上行「活跃」门（字节/秒）。低于此视为 proxy 没在实质发包（空闲 / 全直连）→ 不判死。
    /// 取 256 B/s：滤掉 keepalive / 心跳这类零星字节，又能抓住「用户在重试加载」的真实上行。
    public static let uplinkActiveBytesPerSec: Int64 = 256

    /// 下行「持平」门（字节/秒）。低于此视为「几乎没有回流」（≈0）。取 128 B/s：
    /// 活着的连接哪怕只回 ACK 也远超它；真死的节点回 0 —— 两者清晰可分。
    public static let downlinkFlatBytesPerSec: Int64 = 128

    /// 正常采样间隔 ≈2s。超过此值判为挂起 / 时钟跳变 → 丢弃该窗、重建 baseline。
    /// 取 8s（≈4 个采样周期没到）：吸收定时器抖动，又能抓住真正的睡眠跳变。
    public static let maxSampleGapSeconds: TimeInterval = 8

    // MARK: - 状态

    /// 当前对外判定。初始 healthy。
    public private(set) var state: NodeHealth = .healthy

    private struct Sample { var up: Int64; var down: Int64; var at: Date }

    /// 上一条被采纳的样本（增量的参照）。nil = 判定空窗（等下一条重建 baseline）。
    private var baseline: Sample?
    /// grace 截止时刻；`at < graceUntil` 内不允许判 suspect。
    private var graceUntil: Date?
    /// 「坏窗」连续成立的起点；nil = 当前不在坏窗连续段里。
    private var suspectSince: Date?

    public init() {}

    // MARK: - 事件

    /// switch / reconfigure / restart 后调：作废旧 baseline，进入判定空窗。
    /// 已 latch 的 suspect 一并清掉（我们已经在换节点了，旧判定翻篇）。
    public mutating func resetBaseline() {
        baseline = nil
        graceUntil = nil
        suspectSince = nil
        state = .healthy
    }

    // MARK: - 采样

    /// 喂一条 proxy 累计计数样本，返回**当前**判定。
    /// - Parameters:
    ///   - proxyUplinkTotal: proxy outbound 累计上行字节（本 xray 会话内单调，重启归零）。
    ///   - proxyDownlinkTotal: proxy outbound 累计下行字节。
    ///   - at: 采样时刻（调用方喂，纯逻辑不读系统时钟）。
    @discardableResult
    public mutating func ingest(proxyUplinkTotal up: Int64, proxyDownlinkTotal down: Int64, at now: Date) -> NodeHealth {
        let sample = Sample(up: up, down: down, at: now)

        // 判定空窗 / 首采：建 baseline + 起 grace，本条不出判定。
        guard let base = baseline else {
            establishBaseline(sample)
            return state
        }

        let dt = now.timeIntervalSince(base.at)

        // 睡眠跳变 / 时钟跳变 / 计数器回退（xray 重启归零）→ 丢弃该窗、重建 baseline + 重新宽限。
        if dt > Self.maxSampleGapSeconds || up < base.up || down < base.down {
            establishBaseline(sample)
            return state
        }

        // 非递增时间（重复 / 乱序）：忽略，不推进 baseline。
        guard dt > 0 else { return state }

        let upRate = Double(up - base.up) / dt
        let downRate = Double(down - base.down) / dt
        baseline = sample   // 推进参照点

        let uplinkActive = upRate >= Double(Self.uplinkActiveBytesPerSec)
        let downlinkActive = downRate >= Double(Self.downlinkFlatBytesPerSec)
        let inGrace = graceUntil.map { now < $0 } ?? false

        if uplinkActive && !downlinkActive {
            // 坏窗：上行在涨、下行持平。
            if inGrace {
                // 起手宽限内不判、不累计。
                suspectSince = nil
            } else if state == .suspect {
                // 已 suspect：latch，等 resetBaseline 或下行回流来清。
            } else {
                if suspectSince == nil { suspectSince = base.at }   // 连续段起点 = 本间隔起点
                if let since = suspectSince, now.timeIntervalSince(since) >= Self.suspectSustainSeconds {
                    state = .suspect
                    suspectSince = nil
                }
            }
        } else if downlinkActive {
            // 有下行回流 = 节点确实活着 → 清坏窗连续段 + 解除 suspect（恢复侧）。
            suspectSince = nil
            state = .healthy
        } else {
            // 空闲（上行也不活跃）：是空闲不是死。清连续段；未 latch 时保持 healthy。
            suspectSince = nil
            if state != .suspect { state = .healthy }
            // 已 latch 的 suspect 在纯空闲下保持（保守：宁可多提醒），等回流或 reset 才清。
        }
        return state
    }

    private mutating func establishBaseline(_ sample: Sample) {
        baseline = sample
        graceUntil = sample.at.addingTimeInterval(Self.graceSeconds)
        suspectSince = nil
        state = .healthy
    }
}
