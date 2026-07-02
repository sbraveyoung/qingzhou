import Foundation

/// 「浏览器可能在用加密 DNS（DoH）」的启发式判定。
///
/// 背景：轻舟靠 FakeDNS 拦截明文 DNS 才能把连接映射回域名；浏览器开了 DoH（加密 DNS）
/// 时解析不经过隧道 DNS，连接只剩裸 IP —— 连接页/域名分析大面积显示 IP 不是 bug，
/// 但用户不知道原因会以为坏了（需要一条可关闭的说明）。
///
/// 判定：最近连接里裸 IP 占比 **>50% 且 >20 条** 才提示。两个都取严格大于 ——
/// 小样本占比波动大，且个别 CDN/直连 IP 本来就没有域名，宁可保守不误报。
public enum DoHDetector {

    /// 触发所需的最少裸 IP 连接数（严格大于）。
    public static let minBareIPCount = 20
    /// 触发所需的裸 IP 占比（严格大于）。
    public static let minBareIPShare = 0.5

    public static func isLikelyDoH(bareIPCount: Int, totalCount: Int) -> Bool {
        guard totalCount > 0, bareIPCount > minBareIPCount else { return false }
        return Double(bareIPCount) / Double(totalCount) > minBareIPShare
    }

    /// 直接吃连接列表（UI 用）：按 `HostClassifier.isBareIP` 数裸 IP。
    public static func isLikelyDoH(connections: [Connection]) -> Bool {
        let bare = connections.count(where: { HostClassifier.isBareIP($0.targetHost) })
        return isLikelyDoH(bareIPCount: bare, totalCount: connections.count)
    }
}
