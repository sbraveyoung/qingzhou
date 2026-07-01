#if os(macOS)
import NetworkExtension

/// 启用 / 停用 macOS 内容过滤扩展（来源 App 标注）。
///
/// 启用时系统会弹窗让用户授权「允许"轻舟"过滤网络内容」。扩展本身只观测、一律放行，
/// 把「源端口 → 来源 App」写进 App Group，主 App 用它给连接列表标注是哪个 App。
/// 需要 content-filter-provider entitlement（Apple 特批）+ 用户授权，缺任一项 enable 会 throw。
@MainActor
public enum ContentFilterManager {

    public static var isEnabled: Bool {
        NEFilterManager.shared().isEnabled
    }

    public static func enable() async throws {
        let manager = NEFilterManager.shared()
        try await manager.loadFromPreferences()
        if manager.providerConfiguration == nil {
            let config = NEFilterProviderConfiguration()
            config.filterSockets = true    // 我们要的是 socket 级的 flow（含来源 App）
            config.filterPackets = false
            manager.providerConfiguration = config
        }
        manager.localizedDescription = "轻舟 · 来源 App 标注"
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }

    public static func disable() async throws {
        let manager = NEFilterManager.shared()
        try await manager.loadFromPreferences()
        guard manager.providerConfiguration != nil else { return }
        manager.isEnabled = false
        try await manager.saveToPreferences()
    }
}
#endif
