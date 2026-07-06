import SwiftUI

/// 「忽略 IP」过滤开关 —— 连接页和域名分析页共用。
///
/// - 图标 + 文字并显（`.titleAndIcon`），第一眼就能看懂是干什么的。
/// - **临时状态、不持久化**：绑定 ConnectionsView 的 `@State`，经 Binding 传给
///   域名分析页（两页联动）；离开连接页视图销毁即自动复位为关闭。
/// - 开启时按钮呈选中高亮态（`.toggleStyle(.button)`），让用户看得出过滤在生效。
struct IgnoreIPToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            // iOS 的 ToolbarItem 会把 Label 渲染成 icon-only（.titleAndIcon 常不生效）。
            // 这个开关在域名分析页放在 toolbar 里，iOS 用 HStack 强制图标+文字横排；
            // macOS 用 Label 即可（用户已验收 macOS 现状，别动）。
            #if os(iOS)
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                Text("忽略 IP")
            }
            #else
            Label("忽略 IP", systemImage: "eye.slash")
                .labelStyle(.titleAndIcon)
            #endif
        }
        .toggleStyle(.button)
        .help("隐藏目标是纯 IP（没有域名）的条目；离开页面自动恢复")
    }
}

/// 「隐藏 DNS」过滤开关 —— 与「忽略 IP」同款交互（临时、不持久化、两页联动）。
/// 隧道内部 xray 向上游 DNS（223.5.5.5 / 8.8.8.8 / 1.1.1.1）查询本身也是连接，
/// 不是用户主动访问，开这个开关把它们从列表 / 统计里藏掉。
struct HideDNSToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            #if os(iOS)
            HStack(spacing: 4) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                Text("隐藏 DNS")
            }
            #else
            Label("隐藏 DNS", systemImage: "point.3.filled.connected.trianglepath.dotted")
                .labelStyle(.titleAndIcon)
            #endif
        }
        .toggleStyle(.button)
        .help("隐藏隧道内部向上游 DNS 服务器（如 8.8.8.8:53）的解析查询；离开页面自动恢复")
    }
}
