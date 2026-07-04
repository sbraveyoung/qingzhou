import Foundation

/// 从 App Store（iTunes Lookup API）解出的最新版本信息（我们关心的最小子集）。
public struct AppStoreVersionInfo: Sendable, Equatable {
    /// `results[0].version` —— App Store 上架的最新版本号（如 "1.2.0"）。
    public let version: String
    /// `results[0].releaseNotes` —— 更新说明；可能缺失。
    public let releaseNotes: String?
    /// `results[0].trackViewUrl` —— App Store 页面链接，「更新」按钮用它打开。
    public let trackViewURL: URL?

    public init(version: String, releaseNotes: String? = nil, trackViewURL: URL? = nil) {
        self.version = version
        self.releaseNotes = releaseNotes
        self.trackViewURL = trackViewURL
    }
}

/// 待向用户提示的「发现新版本」（RootView 更新 alert 的数据源）。
public struct AvailableUpdate: Sendable, Equatable, Identifiable {
    public var id: String { version }
    public let version: String
    public let releaseNotes: String?
    public let trackViewURL: URL?

    public init(version: String, releaseNotes: String? = nil, trackViewURL: URL? = nil) {
        self.version = version
        self.releaseNotes = releaseNotes
        self.trackViewURL = trackViewURL
    }
}

/// App 内更新提醒的纯逻辑（无 IO，可单测）：语义化版本比较 + 是否该提示。
public enum UpdateChecker {

    /// 语义化版本比较：按 `.` 分段做**数值**比较（"1.2.0" < "1.10.0"，不能按字符串比大小）。
    ///
    /// 兜底约定（`shouldPrompt` 依赖它绝不 crash）：
    /// - 段数不等时，短的一方缺失段补 0（"1.2" == "1.2.0"）。
    /// - 每段只取前导数字（"1.2.0-beta" 的 "0-beta" → 0；纯非数字段 → 0）。
    /// - 前导零按数值处理（"1.02" == "1.2"）。
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = segments(a)
        let pb = segments(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func segments(_ v: String) -> [Int] {
        let trimmed = v.trimmingCharacters(in: .whitespaces)
        // omittingEmptySubsequences: false —— "" 也产出一段（[""] → [0]），空串不会被当成「无版本」。
        return trimmed.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    /// 是否应向用户提示更新。
    ///
    /// - Parameters:
    ///   - latest: App Store 最新版本号。**nil / 空 = lookup 无结果（未上架）或查询失败 → 不提示**。
    ///   - current: 当前 App 版本（`CFBundleShortVersionString`）。
    ///   - ignored: 用户已「忽略此版本」的版本号（"" = 从未忽略）。
    /// - Returns: `latest` 存在、比 `current` 更新、且比 `ignored` 更新时才为 true。
    ///            —— 已忽略的那个版本（及更旧的忽略记录）不再提示，出了更新的版本才再提示。
    public static func shouldPrompt(latest: String?, current: String, ignored: String) -> Bool {
        guard let latest, !latest.isEmpty else { return false }
        guard compareVersions(latest, current) == .orderedDescending else { return false }
        guard ignored.isEmpty || compareVersions(latest, ignored) == .orderedDescending else { return false }
        return true
    }
}
