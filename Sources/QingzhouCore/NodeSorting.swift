import Foundation

extension Array where Element == Node {
    /// 按指定顺序排序节点。延迟排序时，nil 视为正无穷。
    public func sorted(by order: NodeSortOrder) -> [Node] {
        switch order {
        case .name:
            return sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        case .latency:
            return sorted { lhs, rhs in
                let l = lhs.lastLatencyMs ?? .max
                let r = rhs.lastLatencyMs ?? .max
                if l == r {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return l < r
            }
        }
    }
}
