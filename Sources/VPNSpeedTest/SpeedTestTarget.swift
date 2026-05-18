import Foundation

/// 内置测速目标。覆盖国内外主流站点，便于直观判断节点对各类服务的可用性。
public enum SpeedTestTarget: String, CaseIterable, Sendable, Codable {
    case bilibiliCN
    case bilibiliHKMOTW
    case google
    case anthropic
    case chatgpt
    case claude
    case gemini
    case tiktok
    case youtube

    public var displayName: String {
        switch self {
        case .bilibiliCN:    return "哔哩哔哩大陆"
        case .bilibiliHKMOTW:return "哔哩哔哩港澳台"
        case .google:        return "Google"
        case .anthropic:     return "Anthropic"
        case .chatgpt:       return "ChatGPT"
        case .claude:        return "Claude"
        case .gemini:        return "Gemini"
        case .tiktok:        return "TikTok"
        case .youtube:       return "YouTube"
        }
    }

    public var url: URL {
        // 选用 generate_204 风格或首页 HEAD 路径，避免下大资源
        switch self {
        case .bilibiliCN:     return URL(string: "https://www.bilibili.com/")!
        case .bilibiliHKMOTW: return URL(string: "https://www.bilibili.tv/")!
        case .google:         return URL(string: "https://www.google.com/generate_204")!
        case .anthropic:      return URL(string: "https://www.anthropic.com/")!
        case .chatgpt:        return URL(string: "https://chatgpt.com/")!
        case .claude:         return URL(string: "https://claude.ai/")!
        case .gemini:         return URL(string: "https://gemini.google.com/")!
        case .tiktok:         return URL(string: "https://www.tiktok.com/")!
        case .youtube:        return URL(string: "https://www.youtube.com/generate_204")!
        }
    }
}
