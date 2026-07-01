import Foundation
import QingzhouCore
import QingzhouProtocols

/// 一个订阅响应解析后的结果。
public struct SubscriptionPayload: Sendable {
    public var nodes: [Node]
    public var failedLines: [(line: String, error: Error)]
    public var userInfo: SubscriptionUserInfo?

    public init(
        nodes: [Node],
        failedLines: [(line: String, error: Error)] = [],
        userInfo: SubscriptionUserInfo? = nil
    ) {
        self.nodes = nodes
        self.failedLines = failedLines
        self.userInfo = userInfo
    }
}

/// HTTP 响应头 `Subscription-Userinfo` 的解析结果。
///
/// 格式：`upload=N; download=N; total=N; expire=UNIXTIME`，分号或逗号分隔，字段都可能缺失。
public struct SubscriptionUserInfo: Sendable, Equatable {
    public var upload: Int64?
    public var download: Int64?
    public var total: Int64?
    public var expire: Date?

    public init(upload: Int64? = nil, download: Int64? = nil, total: Int64? = nil, expire: Date? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }

    public var usedBytes: Int64? {
        switch (upload, download) {
        case let (.some(u), .some(d)): return u + d
        case let (.some(u), .none):    return u
        case let (.none, .some(d)):    return d
        case (.none, .none):           return nil
        }
    }

    public static func parse(_ header: String) -> SubscriptionUserInfo {
        var info = SubscriptionUserInfo()
        let parts = header.split(whereSeparator: { $0 == ";" || $0 == "," })
        for part in parts {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            let key = kv[0].lowercased()
            let value = kv[1]
            switch key {
            case "upload":
                info.upload = Int64(value)
            case "download":
                info.download = Int64(value)
            case "total":
                info.total = Int64(value)
            case "expire":
                if let ts = TimeInterval(value), ts > 0 {
                    info.expire = Date(timeIntervalSince1970: ts)
                }
            default:
                break
            }
        }
        return info
    }
}
