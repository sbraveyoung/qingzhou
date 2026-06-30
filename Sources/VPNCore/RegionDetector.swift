import Foundation

/// 从节点名里识别地区。
///
/// 机场节点名五花八门，但地区信息几乎总在名字里，形式无非几种：
///   - 中文名：`香港`、`日本`、`新加坡`、`美国`
///   - 国家/地区码：`HK`、`JP`、`SG`、`US`
///   - 英文名：`Hong Kong`、`Japan`
///   - 旗帜 emoji：🇭🇰 🇯🇵 🇸🇬
///
/// 识别策略：按关键词匹配，返回统一的中文地区名（用于 UI 展示 + 排除/优先设置的 key）。
/// 没匹配上的归为 `nil`（UI 里显示成「其它」）。
public enum RegionDetector {

    /// (统一地区名, 匹配关键词)。关键词大小写不敏感。
    /// 顺序敏感：先匹配更具体的（如「台湾」在「湾」之前不是问题，但把高歧义的放后面）。
    public static let table: [(region: String, keywords: [String])] = [
        ("香港", ["香港", "HK", "HongKong", "Hong Kong", "🇭🇰"]),
        ("台湾", ["台湾", "臺灣", "台灣", "TW", "Taiwan", "🇹🇼"]),
        ("日本", ["日本", "JP", "Japan", "东京", "東京", "大阪", "Tokyo", "Osaka", "🇯🇵"]),
        ("新加坡", ["新加坡", "狮城", "獅城", "SG", "Singapore", "🇸🇬"]),
        ("韩国", ["韩国", "韓國", "KR", "Korea", "首尔", "首爾", "Seoul", "🇰🇷"]),
        ("美国", ["美国", "美國", "US", "USA", "United States", "America", "硅谷", "洛杉矶", "Los Angeles", "🇺🇸"]),
        ("英国", ["英国", "英國", "UK", "GB", "United Kingdom", "London", "伦敦", "倫敦", "🇬🇧"]),
        ("德国", ["德国", "德國", "DE", "Germany", "法兰克福", "Frankfurt", "🇩🇪"]),
        ("荷兰", ["荷兰", "荷蘭", "NL", "Netherlands", "阿姆斯特丹", "Amsterdam", "🇳🇱"]),
        ("法国", ["法国", "法國", "FR", "France", "巴黎", "Paris", "🇫🇷"]),
        ("加拿大", ["加拿大", "CA", "Canada", "🇨🇦"]),
        ("澳大利亚", ["澳大利亚", "澳洲", "AU", "Australia", "悉尼", "Sydney", "🇦🇺"]),
        ("俄罗斯", ["俄罗斯", "俄羅斯", "RU", "Russia", "莫斯科", "Moscow", "🇷🇺"]),
        ("印度", ["印度", "IN", "India", "孟买", "Mumbai", "🇮🇳"]),
        ("土耳其", ["土耳其", "TR", "Turkey", "🇹🇷"]),
        ("马来西亚", ["马来西亚", "馬來西亞", "MY", "Malaysia", "🇲🇾"]),
        ("泰国", ["泰国", "泰國", "TH", "Thailand", "曼谷", "Bangkok", "🇹🇭"]),
        ("越南", ["越南", "VN", "Vietnam", "🇻🇳"]),
        ("菲律宾", ["菲律宾", "菲律賓", "PH", "Philippines", "🇵🇭"]),
        ("阿根廷", ["阿根廷", "AR", "Argentina", "🇦🇷"]),
        ("巴西", ["巴西", "BR", "Brazil", "🇧🇷"]),
    ]

    /// 从节点名识别地区，返回统一中文地区名；识别不出返回 nil。
    public static func detect(from name: String) -> String? {
        let upper = name.uppercased()
        for (region, keywords) in table {
            for kw in keywords {
                // 中文 / emoji 直接 contains；英文用大写比对避免大小写漏匹配
                if kw.range(of: "[A-Za-z]", options: .regularExpression) != nil {
                    if upper.contains(kw.uppercased()) { return region }
                } else if name.contains(kw) {
                    return region
                }
            }
        }
        return nil
    }

    /// UI 兜底名：识别不出时显示「其它」。
    public static let unknownDisplayName = "其它"
}
