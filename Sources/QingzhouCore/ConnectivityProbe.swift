import Foundation

/// 连通性探测 / 经代理测速的目标清单。
///
/// 为什么不是单一 `google.com/generate_204`（真机踩过的坑）：很多机场节点的出口线路
/// 对 Google 会 **reset**（"connection reset by peer"），但对 Cloudflare / Apple / 其他站点
/// 完全正常。用 Google 作唯一探测点 → 连通性哨兵误报「无法访问外网」、经代理测速误报失败，
/// 尽管节点其实好好的。所以：**多目标、任一通过即算联网**。
///
/// 目标都返回极小响应（204 / 短 HTML），不下大资源、不消耗流量。
public enum ConnectivityProbe {
    /// 内置探测目标，按可靠性排序。任一成功即视为链路可用。
    /// Cloudflare / Apple 全球 POP、极少被单节点出口 reset，排前面；
    /// Google 系放最后（作单一探测点会误报，作候选之一仍有价值）。
    public static let presets: [ProbeTarget] = [
        ProbeTarget(id: "cloudflare", name: "Cloudflare", url: "https://cp.cloudflare.com/generate_204"),
        ProbeTarget(id: "apple",      name: "Apple",      url: "https://captive.apple.com/hotspot-detect.html"),
        ProbeTarget(id: "gstatic",    name: "Google（gstatic）", url: "https://www.gstatic.com/generate_204"),
        ProbeTarget(id: "google",     name: "Google", url: "https://www.google.com/generate_204"),
    ]

    /// 经代理测速的默认目标（单点，要给出稳定可比的延迟数字）——选 Cloudflare：
    /// 全球 POP 分布、几乎不被节点出口 reset，比 Google 更能公平反映「节点出口质量」。
    public static let defaultProxiedTarget = "https://cp.cloudflare.com/generate_204"

    /// 连通性哨兵按序尝试的完整目标列表：用户指定的（若有）排最前，再接内置候选。
    /// 任一通过即算联网 —— 一个节点出口能到 Cloudflare 却 reset Google，明显是好节点。
    public static func sentinelTargets(preferred: String?) -> [String] {
        let builtin = presets.map(\.url)
        guard let preferred, !preferred.isEmpty, URL(string: preferred) != nil else {
            return builtin
        }
        return [preferred] + builtin.filter { $0 != preferred }
    }
}

/// 一个探测目标（设置页 Picker 展示用）。
public struct ProbeTarget: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let url: String
    public init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}
