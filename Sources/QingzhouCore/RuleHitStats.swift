import Foundation

/// 自定义规则的命中计数：按天 × 规则 id 滚动累计，保留最近 30 天。
///
/// 用途：规则页显示「近 30 天命中 N 次」，长期零命中的规则给「可考虑删除」弱提示 ——
/// 帮用户发现规则表里的死条目。
///
/// 口径：只统计 MatchedRuleResolver **认领**了该用户规则的连接（判定与实际路由一致，
/// 见 resolver 的诚实原则），且只算 ConnectionTracker 判定的新连接（同 DomainDailyHistory，
/// 避免 UDP/QUIC 重现灌水）。
///
/// ⚠️ 隐私：命中计数间接反映访问行为。只存本地（Persistence 目录独立文件），
/// **不进 Persistence.Snapshot**，绝不被 iCloud vault 镜像。
public struct RuleHitStats: Codable, Sendable, Equatable {

    public static let defaultKeepDays = 30
    /// 「可考虑删除」提示的最短观察期（天）：跟踪不满这个天数时零命中不提示 ——
    /// 否则功能上线首日所有规则都会被误标成「可删除」。
    public static let minObservedDays = 7

    /// 开始跟踪的时刻（首次创建本结构的时间），观察期判定用。
    public var trackingSince: Date
    /// 天键（"2026-07-02"，同 DomainDailyHistory 口径）→ 规则 id 字符串 → 当天命中次数。
    /// id 用 uuidString 而不是 UUID：UUID 作字典键 JSON 编码会退化成数组对。
    public var days: [String: [String: Int]] = [:]

    public init(trackingSince: Date = Date()) {
        self.trackingSince = trackingSince
    }

    // MARK: - 记录 / 清理

    public mutating func recordHit(_ id: UUID, at date: Date = Date(),
                                   calendar: Calendar = .current) {
        let key = DomainDailyHistory.dayKey(date, calendar: calendar)
        days[key, default: [:]][id.uuidString, default: 0] += 1
    }

    /// 只保留最近 `keepDays` 天（含今天）；解析不了的天键一并清掉。
    public mutating func prune(keepDays: Int = defaultKeepDays, now: Date = Date(),
                               calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -(keepDays - 1),
                                         to: calendar.startOfDay(for: now)) else { return }
        days = days.filter { key, _ in
            guard let day = DomainDailyHistory.parseDayKey(key, calendar: calendar) else { return false }
            return day >= cutoff
        }
    }

    // MARK: - 查询

    /// 窗口内（days 里现存的全部天）该规则的命中总数。
    public func hitCount(for id: UUID) -> Int {
        let key = id.uuidString
        return days.values.reduce(0) { $0 + ($1[key] ?? 0) }
    }

    /// 该规则是否是「可考虑删除」候选：跟踪已满观察期且窗口内零命中。
    public func isIdleCandidate(_ id: UUID, now: Date = Date(),
                                calendar: Calendar = .current) -> Bool {
        guard let matureAt = calendar.date(byAdding: .day, value: Self.minObservedDays,
                                           to: trackingSince), now >= matureAt else { return false }
        return hitCount(for: id) == 0
    }
}
