import Foundation
import QingzhouCore
import QingzhouProtocols

/// 订阅响应体解析器（无网络副作用，便于单测）。
public enum SubscriptionParser {
    /// 解析订阅响应体。订阅源主流编码方式：
    /// 1. 整体 base64，解码后是按行分隔的链接；
    /// 2. 明文按行分隔的链接（部分订阅商如 yizhihongxing 也支持这种）；
    /// 3. 单个明文链接（手动添加单服务器场景）；
    /// 4. **Clash / Mihomo / Stash YAML 配置**（含 `proxies:` 顶层 key）。
    ///
    /// 策略：先嗅探 Clash YAML（最特征明显），不是再走 base64/明文链接路径。
    public static func parse(body: String, userInfoHeader: String? = nil) -> SubscriptionPayload {
        let info = userInfoHeader.map(SubscriptionUserInfo.parse)

        // 优先识别 Clash YAML
        if ClashConfigParser.isClashConfig(body) {
            do {
                let (nodes, errs) = try ClashConfigParser.parse(body)
                let failedLines = errs.map { (line: $0.name, error: NSError(
                    domain: "ClashConfig", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: $0.reason]
                ) as Error) }
                return SubscriptionPayload(nodes: nodes, failedLines: failedLines, userInfo: info)
            } catch {
                // 解析失败就 fall through 到链接路径
            }
        }

        let text = decodeIfBase64(body)
        let (nodes, errors) = ProxyURLParser.parseBatch(text)
        return SubscriptionPayload(nodes: nodes, failedLines: errors, userInfo: info)
    }

    /// 启发式：去掉空白后，如果整段看起来像 base64 且能解码，就解码，否则按原样返回。
    static func decodeIfBase64(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 含 "://" 几乎可以肯定是明文链接
        if trimmed.contains("://") { return body }
        // 长度过短或含明显非 base64 字符，跳过
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_\n\r ")
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return body
        }
        if let decoded = String.fromPermissiveBase64(trimmed) {
            return decoded
        }
        return body
    }
}
