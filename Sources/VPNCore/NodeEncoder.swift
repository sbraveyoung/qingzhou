import Foundation

/// 把 `Node` 反序列化成 `trojan:// / vmess:// / ...` 分享链接形式。
/// 调用方主要有两个：
///   1. QR 分享 UI
///   2. 启动 VPN 时把 Node 喂给 xray-core 之前先转 share link（libXray 内置 share link → JSON 转换）
public enum NodeEncoder {

    /// 把节点编码成可分享的链接字符串。失败返回 nil（极少发生 —— 主要是 URL 字段无法 percent-encode）。
    public static func shareLink(_ node: Node) -> String? {
        var queryItems: [URLQueryItem] = []
        for (k, v) in node.parameters.sorted(by: { $0.key < $1.key }) {
            queryItems.append(URLQueryItem(name: k, value: v))
        }
        var comps = URLComponents()
        comps.scheme = node.protocolType.urlScheme
        comps.host = node.host
        comps.port = node.port
        if !queryItems.isEmpty { comps.queryItems = queryItems }
        comps.fragment = node.name

        switch node.protocolType {
        case .trojan, .hysteria2:
            comps.user = node.password
            return comps.url?.absoluteString
        case .vless:
            comps.user = node.uuid
            return comps.url?.absoluteString
        case .shadowsocks:
            // SIP002 形式：ss://base64(method:password)@host:port#name
            let credential = "\(node.cipher ?? ""):\(node.password ?? "")"
            let b64 = Data(credential.utf8).base64EncodedString()
            comps.user = b64
            return comps.url?.absoluteString
        case .vmess:
            // vmess://base64(json) 形式 —— v2rayN 兼容字段集合
            var json: [String: Any] = [
                "v": "2",
                "ps": node.name,
                "add": node.host,
                "port": "\(node.port)",
                "id": node.uuid ?? "",
                "aid": node.alterId ?? 0,
                "scy": node.cipher ?? "auto"
            ]
            for (k, v) in node.parameters { json[k] = v }
            guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
            return "vmess://" + data.base64EncodedString()
        }
    }
}
