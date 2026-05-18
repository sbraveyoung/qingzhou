import Foundation

extension Data {
    /// Base64 解码，宽松版：自动补齐 padding，并兼容 URL-safe 变体（`-_` → `+/`）。
    /// 订阅源 / 链接里的 base64 经常缺 `=`，标准解码器会直接失败。
    public static func fromPermissiveBase64(_ input: String) -> Data? {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        let remainder = s.count % 4
        if remainder > 0 {
            s.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: s)
    }
}

extension String {
    /// 同上，方便解码成 UTF-8 字符串。
    public static func fromPermissiveBase64(_ input: String) -> String? {
        guard let data = Data.fromPermissiveBase64(input) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
