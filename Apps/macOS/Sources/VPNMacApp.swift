// 示例：macOS App 入口。
//
// 包含两个 Scene：
// - WindowGroup 提供常规窗口
// - MenuBarExtra 提供状态栏菜单（macOS 13+）
//
// 同样，真要让代理工作需要 Network Extension Target 和 entitlements，详见 docs/BUILD.md。

import SwiftUI
import VPNApp
import VPNLogging
import VPNCore

@main
struct VPNMacApp: App {
    @State private var state: AppState = AppState(
        logger: Logger(capacity: 10000, minimumLevel: .debug)
    )

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .frame(minWidth: 880, minHeight: 560)
                .preferredColorScheme(colorScheme(for: state.settings.theme))
                .environment(\.locale, LocaleResolver.locale(for: state.settings.language))
                .task {
                    state.startSchedulers()
                    state.applyMacSystemPreferences()
                    if state.remoteRules.isEmpty {
                        await state.refreshRemoteRules()
                    }
                    await state.refreshPublicIPInfo()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { } // 关掉 ⌘N
        }

        MenuBarExtra {
            StatusBarMenu(state: state)
                .environment(\.locale, LocaleResolver.locale(for: state.settings.language))
        } label: {
            // 已连接时用满格三角，断开时用空心三角
            Image(systemName: state.isVPNRunning ? "triangle.fill" : "triangle")
        }
        .menuBarExtraStyle(.menu)
    }

    private func colorScheme(for theme: AppearanceTheme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
