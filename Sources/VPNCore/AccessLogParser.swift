import Foundation

/// 解析 xray-core 的 access log 行 → 结构化连接信息。
///
/// xray 的 `AccessMessage.String()` 格式（开了 sniffing 后目标是域名而非 IP）：
///   `from <src> accepted <net>:<host>:<port> [<inboundTag> -> <outboundTag>]`
/// 可能带时间戳前缀（`2026/07/01 12:00:00 from ...`）、可能 `rejected`、可能无 detour 段。
///
/// 这是 (a) 管道里「per-连接/per-域名」那条支线的纯逻辑核心：appex 让 xray 把 access log
/// 写进 App Group 文件，主 app 读出来逐行喂给它 → 连接列表 + 域名每日汇总(E) 的数据源。
public struct AccessLogEntry: Equatable, Sendable {
    public var sourceAddress: String   // ip:port（已去掉可能的 net: 前缀）
    public var network: String         // "tcp" / "udp"
    public var targetHost: String      // 域名或 IP（IPv6 去掉外层方括号）
    public var targetPort: Int
    public var inboundTag: String      // 如 "tun-in"，无 detour 段时为 ""
    public var outboundTag: String     // 如 "proxy" / "direct" / "reject"，无 detour 段时为 ""
    public var accepted: Bool          // accepted=true，rejected=false

    public init(sourceAddress: String, network: String, targetHost: String, targetPort: Int,
                inboundTag: String, outboundTag: String, accepted: Bool) {
        self.sourceAddress = sourceAddress
        self.network = network
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.inboundTag = inboundTag
        self.outboundTag = outboundTag
        self.accepted = accepted
    }
}

public enum AccessLogParser {

    /// 解析一整段日志文本，跳过解析不出的行。
    public static func parse(_ text: String) -> [AccessLogEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    /// 解析单行；不是一条 access 记录（或格式不符）时返回 nil。
    public static func parseLine(_ raw: String) -> AccessLogEntry? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let fromRange = line.range(of: "from ") else { return nil }
        var rest = String(line[fromRange.upperBound...])

        // status: accepted / rejected
        let accepted: Bool
        let statusRange: Range<String.Index>
        if let r = rest.range(of: " accepted ") {
            accepted = true; statusRange = r
        } else if let r = rest.range(of: " rejected ") {
            accepted = false; statusRange = r
        } else {
            return nil
        }
        let source = stripNetworkPrefix(String(rest[..<statusRange.lowerBound])).host  // 只丢前缀
        rest = String(rest[statusRange.upperBound...])

        // 可选 detour 段 [in -> out]。注意用前导空格 " [" 定位，否则会误匹配目标里
        // IPv6 host 的方括号（如 tcp:[2001:db8::1]:443）。
        var inboundTag = "", outboundTag = ""
        var toPart = rest
        if let lb = rest.range(of: " ["),
           let rb = rest.range(of: "]", range: lb.upperBound..<rest.endIndex) {
            toPart = String(rest[..<lb.lowerBound])
            let comps = String(rest[lb.upperBound..<rb.lowerBound]).components(separatedBy: " -> ")
            if comps.count == 2 {
                inboundTag = comps[0].trimmingCharacters(in: .whitespaces)
                outboundTag = comps[1].trimmingCharacters(in: .whitespaces)
            }
        }

        // target: [net:]host:port
        let (host, port, network) = splitTarget(toPart.trimmingCharacters(in: .whitespaces))
        guard let port, !host.isEmpty else { return nil }

        return AccessLogEntry(
            sourceAddress: source.trimmingCharacters(in: .whitespaces),
            network: network,
            targetHost: host,
            targetPort: port,
            inboundTag: inboundTag,
            outboundTag: outboundTag,
            accepted: accepted
        )
    }

    // MARK: - 私有

    /// 去掉 `tcp:` / `udp:` 前缀，返回剩余串 + 识别出的 network（默认 tcp）。
    private static func stripNetworkPrefix(_ s: String) -> (host: String, network: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("tcp:") { return (String(t.dropFirst(4)), "tcp") }
        if t.hasPrefix("udp:") { return (String(t.dropFirst(4)), "udp") }
        return (t, "tcp")
    }

    /// 把 `[net:]host:port` 拆成 host / port / network。从右起第一个冒号切端口；
    /// IPv6 形如 `[::1]:443` 去掉外层方括号。
    private static func splitTarget(_ s: String) -> (host: String, port: Int?, network: String) {
        let (body, network) = stripNetworkPrefix(s)
        guard let lastColon = body.lastIndex(of: ":") else { return (body, nil, network) }
        var host = String(body[..<lastColon])
        let portStr = String(body[body.index(after: lastColon)...])
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return (host, Int(portStr), network)
    }
}

public extension AccessLogEntry {
    /// 映射成应用层 `Connection` 快照。`proxyDisplayName` 传当前节点名（走代理时显示用）。
    /// `matchedRule` 留空——命中哪条规则由上层用 RuleEngine 对 targetHost 反推（E 阶段）。
    func makeConnection(proxyDisplayName: String?) -> Connection {
        let route: String
        switch outboundTag.lowercased() {
        case "direct", "freedom":            route = "DIRECT"
        case "reject", "blackhole", "block": route = "REJECT"
        case "":                             route = accepted ? (proxyDisplayName ?? "PROXY") : "REJECT"
        default:                             route = proxyDisplayName ?? "PROXY"
        }
        let type: ConnectionType
        if network == "udp" { type = .udp }
        else if targetPort == 443 { type = .https }
        else if targetPort == 80 { type = .http }
        else { type = .tcp }
        return Connection(
            targetHost: targetHost,
            sourceAddress: sourceAddress,
            targetAddress: "\(targetHost):\(targetPort)",
            type: type,
            route: route,
            matchedRule: ""
        )
    }
}
