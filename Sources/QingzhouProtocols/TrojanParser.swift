import Foundation
import QingzhouCore

/// 解析 `trojan://password@host:port?sni=...&type=...#name` 形式的链接。
enum TrojanParser {
    static func parse(_ urlString: String) throws -> Node {
        guard let comps = URLComponents(string: urlString) else {
            throw ProxyURLParseError.malformedURL
        }
        guard let host = comps.host, !host.isEmpty else { throw ProxyURLParseError.missingHost }
        guard let port = comps.port else { throw ProxyURLParseError.missingPort }
        guard let password = comps.user?.removingPercentEncoding, !password.isEmpty else {
            throw ProxyURLParseError.missingCredential
        }
        let name = comps.fragment?.removingPercentEncoding ?? "\(host):\(port)"
        let params = Dictionary(
            (comps.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let v = item.value else { return nil }
                return (item.name, v)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return Node(
            name: name,
            protocolType: .trojan,
            host: host,
            port: port,
            password: password,
            parameters: params
        )
    }
}
