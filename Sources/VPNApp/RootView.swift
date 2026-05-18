import SwiftUI
import VPNCore

/// 跨平台根视图。iOS 用 TabView，macOS 用 NavigationSplitView。
public struct RootView: View {
    @Bindable public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        #if os(iOS)
        iOSRoot
        #else
        macOSRoot
        #endif
    }

    #if os(iOS)
    private var iOSRoot: some View {
        // 超过 5 个 tab 时 iPhone 会自动把多出来的塞进 "More" tab。
        TabView {
            NavigationStack { HomeView(state: state) }
                .tabItem { Label("首页", systemImage: "house") }
            NavigationStack { NodesView(state: state) }
                .tabItem { Label("节点", systemImage: "server.rack") }
            NavigationStack { SubscriptionsView(state: state) }
                .tabItem { Label("订阅", systemImage: "tray.full") }
            NavigationStack { RulesView(state: state) }
                .tabItem { Label("规则", systemImage: "list.bullet.rectangle") }
            NavigationStack { ConnectionsView(state: state) }
                .tabItem { Label("连接", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { LogsView(state: state) }
                .tabItem { Label("日志", systemImage: "doc.text.magnifyingglass") }
            NavigationStack { SettingsView(state: state) }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
    #else
    private var macOSRoot: some View {
        NavigationSplitView {
            List {
                NavigationLink("首页") { HomeView(state: state) }
                NavigationLink("节点") { NodesView(state: state) }
                NavigationLink("订阅") { SubscriptionsView(state: state) }
                NavigationLink("规则") { RulesView(state: state) }
                NavigationLink("连接") { ConnectionsView(state: state) }
                NavigationLink("日志") { LogsView(state: state) }
                NavigationLink("设置") { SettingsView(state: state) }
            }
            .navigationTitle("VPN")
            .frame(minWidth: 180)
        } detail: {
            HomeView(state: state)
        }
    }
    #endif
}
