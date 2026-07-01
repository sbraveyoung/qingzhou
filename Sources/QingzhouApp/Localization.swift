import Foundation
import SwiftUI
import QingzhouCore

/// 把 `AppLanguage` 设置映射到 SwiftUI 的 `Locale` 环境值。
/// 一旦应用，所有 `Date.formatted` / `Text(date:)` / 数字 / 相对时间会立刻按目标 locale 渲染。
///
/// 注意：**UI 字符串字面量本身的翻译** 还需要一份 `Localizable.xcstrings`（在 Sources/QingzhouApp/Resources/
/// 里加，参考 docs/CONTRIBUTING.md）。当前仓库只随附了简体中文（开发语言），其他语种的翻译
/// 由社区 PR 提交 —— 提交后 SwiftUI 会自动用 `state.settings.language` 选中的语种。
public enum LocaleResolver {
    public static func locale(for language: AppLanguage) -> Locale {
        switch language {
        case .system:  return Locale.autoupdatingCurrent
        case .zhHans:  return Locale(identifier: "zh-Hans")
        case .zhHant:  return Locale(identifier: "zh-Hant")
        case .en:      return Locale(identifier: "en")
        case .ja:      return Locale(identifier: "ja")
        }
    }
}
