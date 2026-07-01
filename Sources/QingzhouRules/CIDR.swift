import Foundation

/// IPv4 / IPv6 CIDR 解析 + 命中判断。完全自包含，不依赖系统 inet_pton（便于 Linux 跨平台）。
public enum CIDR {

    // MARK: - IPv4

    public struct V4: Equatable, Sendable {
        public let network: UInt32
        public let prefixLength: Int   // 0...32

        public func contains(_ address: UInt32) -> Bool {
            guard prefixLength > 0 else { return true }   // 0.0.0.0/0 全匹配
            let shift = 32 - prefixLength
            return (address >> shift) == (network >> shift)
        }
    }

    public static func parseIPv4(_ s: String) -> V4? {
        let parts = s.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32,
              let addr = ipv4ToUInt32(parts[0]) else {
            return nil
        }
        return V4(network: addr, prefixLength: prefix)
    }

    public static func ipv4ToUInt32(_ s: String) -> UInt32? {
        let octets = s.split(separator: ".").map(String.init)
        guard octets.count == 4 else { return nil }
        var result: UInt32 = 0
        for o in octets {
            guard let v = UInt32(o), v <= 255 else { return nil }
            result = (result << 8) | v
        }
        return result
    }

    // MARK: - IPv6

    public struct V6: Equatable, Sendable {
        public let networkHigh: UInt64
        public let networkLow: UInt64
        public let prefixLength: Int   // 0...128

        public func contains(high: UInt64, low: UInt64) -> Bool {
            if prefixLength == 0 { return true }
            if prefixLength <= 64 {
                let shift = 64 - prefixLength
                return (high >> shift) == (networkHigh >> shift)
            } else {
                if high != networkHigh { return false }
                let shift = 128 - prefixLength
                return (low >> shift) == (networkLow >> shift)
            }
        }
    }

    public static func parseIPv6(_ s: String) -> V6? {
        let parts = s.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 128 else {
            return nil
        }
        guard let (high, low) = ipv6Components(parts[0]) else { return nil }
        return V6(networkHigh: high, networkLow: low, prefixLength: prefix)
    }

    /// IPv6 文本 → 高 64 位 / 低 64 位。支持 `::` 缩写，但不支持 IPv4-mapped 的混合写法。
    public static func ipv6Components(_ s: String) -> (high: UInt64, low: UInt64)? {
        // 处理 `::` 缩写：分两半，分别从左和右填充
        let doubleColon = s.range(of: "::")
        var groups: [UInt16] = []

        if let range = doubleColon {
            let lhs = String(s[..<range.lowerBound])
            let rhs = String(s[range.upperBound...])
            let lhsGroups = lhs.isEmpty ? [] : lhs.split(separator: ":").map(String.init)
            let rhsGroups = rhs.isEmpty ? [] : rhs.split(separator: ":").map(String.init)
            let missing = 8 - (lhsGroups.count + rhsGroups.count)
            if missing < 0 { return nil }
            for g in lhsGroups {
                guard let v = UInt16(g, radix: 16) else { return nil }
                groups.append(v)
            }
            groups.append(contentsOf: repeatElement(UInt16(0), count: missing))
            for g in rhsGroups {
                guard let v = UInt16(g, radix: 16) else { return nil }
                groups.append(v)
            }
        } else {
            for g in s.split(separator: ":") {
                guard let v = UInt16(g, radix: 16) else { return nil }
                groups.append(v)
            }
        }
        guard groups.count == 8 else { return nil }
        let high = (UInt64(groups[0]) << 48) | (UInt64(groups[1]) << 32) | (UInt64(groups[2]) << 16) | UInt64(groups[3])
        let low  = (UInt64(groups[4]) << 48) | (UInt64(groups[5]) << 32) | (UInt64(groups[6]) << 16) | UInt64(groups[7])
        return (high, low)
    }
}
