import Foundation

/// 订阅源元数据。流量额度信息从 HTTP 响应头 `Subscription-Userinfo` 解析。
public struct Subscription: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var lastUpdatedAt: Date?
    public var nodeCount: Int
    public var usedBytes: Int64?        // upload + download
    public var totalBytes: Int64?
    public var expiresAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        lastUpdatedAt: Date? = nil,
        nodeCount: Int = 0,
        usedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUpdatedAt = lastUpdatedAt
        self.nodeCount = nodeCount
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.expiresAt = expiresAt
    }

    /// 已用流量占比 0...1；信息缺失时返回 nil。
    public var usageRatio: Double? {
        guard let used = usedBytes, let total = totalBytes, total > 0 else { return nil }
        return min(1.0, Double(used) / Double(total))
    }
}
