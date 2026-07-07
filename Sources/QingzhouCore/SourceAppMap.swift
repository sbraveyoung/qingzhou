import Foundation

/// content filter 扩展经 XPC 给出的「源端口 → 来源 App」映射（macOS 来源 App 标注管线）。
///
/// XPC 线上格式仍是 [String: String]（selector 不变，新旧扩展二进制兼容）：
///   - 旧扩展：值 = "bundleID" → 退回纯端口匹配（原有行为）；
///   - 新扩展：值 = "bundleID\t<unix秒>"，\t 后是 filter 观测到该 flow 的时刻
///     （编码侧在 Apps/Filter-macOS/FilterDataProvider.swift，两侧格式必须同步改）。
///
/// 带时间戳的条目按「端口 + 时间窗」认领：flow 观测发生在建连一瞬，连接的 openedAt 是
/// ingest 时刻（真实建连 + ≤2s 轮询滞后），二者同机同钟，正常间隔只有几秒。
/// |seenAt − openedAt| 超窗即视为端口已被系统回收复用 —— 宁可留「未知来源」也不误标。
public struct SourceAppMap: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        let bundleID: String
        /// nil = 旧扩展条目（无时间戳）或时间戳解析失败 → 不做时间窗校验。
        let seenAt: Date?
    }

    private var entries: [String: Entry]

    /// 时间窗（秒）。要吸收：XPC/access-log 各自的轮询滞后（各 ≤2s）+ 高负载下的日志
    /// 落盘延迟；又不能大到把「几十秒后端口被复用」也认进来。
    public static let matchWindow: TimeInterval = 15

    public init() { entries = [:] }

    public init(raw: [String: String]) {
        entries = raw.mapValues { value in
            guard let tab = value.firstIndex(of: "\t") else {
                return Entry(bundleID: value, seenAt: nil)
            }
            let bundleID = String(value[..<tab])
            let seenAt = TimeInterval(value[value.index(after: tab)...])
                .map { Date(timeIntervalSince1970: $0) }
            return Entry(bundleID: bundleID, seenAt: seenAt)
        }
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func bundleID(forPort port: String, openedAt: Date, window: TimeInterval = Self.matchWindow) -> String? {
        guard let entry = entries[port] else { return nil }
        if let seenAt = entry.seenAt, abs(seenAt.timeIntervalSince(openedAt)) > window {
            return nil
        }
        return entry.bundleID
    }
}
