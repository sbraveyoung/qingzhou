import Foundation

/// 流量分流策略。
public enum ProxyMode: String, Codable, Sendable, CaseIterable {
    case global   // 全局代理：所有流量走代理
    case rule     // 规则代理：按规则集匹配
    case direct   // 直连：所有流量绕过代理
}
