import Foundation

public enum ByteFormatter {
    /// 把字节数格式化成 `1.23 GB` 这种。负数按 0 处理。
    public static func format(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var idx = 0
        var v = value
        while v >= 1024 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        if idx == 0 {
            return "\(Int(v)) \(units[idx])"
        }
        return String(format: "%.2f %@", v, units[idx])
    }
}
