import Foundation
import QingzhouCore

public enum ProxyURLParseError: Error, Equatable, Sendable {
    case unsupportedScheme(String)
    case malformedURL
    case missingHost
    case missingPort
    case missingCredential
    case invalidPort(String)
    case invalidBase64
    case invalidJSON(String)
}

/// 协议链接解析入口。根据 URL scheme 分发到具体协议解析器。
public enum ProxyURLParser {
    /// 解析单条节点链接。
    public static func parse(_ urlString: String) throws -> Node {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.range(of: "://") else {
            throw ProxyURLParseError.malformedURL
        }
        let scheme = String(trimmed[..<schemeEnd.lowerBound])
        guard let proto = ProxyProtocol.from(scheme: scheme) else {
            throw ProxyURLParseError.unsupportedScheme(scheme)
        }
        switch proto {
        case .trojan:      return try TrojanParser.parse(trimmed)
        case .shadowsocks: return try ShadowsocksParser.parse(trimmed)
        case .vmess:       return try VMessParser.parse(trimmed)
        case .vless:       return try VLESSParser.parse(trimmed)
        case .hysteria2:   return try Hysteria2Parser.parse(trimmed)
        }
    }

    /// 解析一批链接（每行一条），忽略空行和无法识别的行；返回成功解析到的节点。
    public static func parseBatch(_ text: String) -> (nodes: [Node], errors: [(String, Error)]) {
        var nodes: [Node] = []
        var errors: [(String, Error)] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            do {
                nodes.append(try parse(line))
            } catch {
                errors.append((line, error))
            }
        }
        return (nodes, errors)
    }
}
