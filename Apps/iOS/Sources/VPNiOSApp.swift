// iOS App 入口。
//
// **注意**：主 App 不要 `import XrayCore`。XrayCore 拖入 LibXray.xcframework（85 MB
// Go runtime），dyld 在进程启动时把它整个加载完才进 main()，会让 app 黑屏 1–3 秒。
// share link → xray 配置的转换都在 Extension（Apps/Tunnel-Shared/PacketTunnelProvider.swift）
// 里跑 —— Extension 进程独立加载 LibXray，跟主 App 启动无关。

import SwiftUI
import VPNApp
import VPNLogging
import VPNCore

@main
struct VPNiOSApp: App {
    @State private var state: AppState = AppState(
        logger: Logger(capacity: 5000, minimumLevel: .debug)
    )

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .preferredColorScheme(colorScheme(for: state.settings.theme))
                .environment(\.locale, LocaleResolver.locale(for: state.settings.language))
                .task {
                    // 调度器 + 网络初始化 —— 都是 async，主线程立即让出
                    state.startSchedulers()
                    if state.remoteRules.isEmpty {
                        await state.refreshRemoteRules()
                    }
                    await state.refreshPublicIPInfo()
                }
        }
    }

    private func colorScheme(for theme: AppearanceTheme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
