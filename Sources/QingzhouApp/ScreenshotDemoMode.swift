import Foundation
import QingzhouCore

/// App Store 截图专用 demo 模式（fastlane snapshot 的思路）。
///
/// 仅当进程带 `-qz-screenshot` launch argument 时激活——只有模拟器上
/// `simctl launch <udid> <bundle-id> -qz-screenshot -qz-tab nodes` 这么传，
/// 生产/正式包不会以该参数启动。激活后：
///   - 注入一套演示配置（节点/订阅/规则，带真实感延迟、双延迟 chip、倍率标注）；
///   - 伪造「已连接」状态并按秒喂波形样本（模拟器跑不了 NE，真连不上）；
///   - `-qz-tab home|nodes|subscriptions|rules|settings` 指定落到哪个 tab；
///   - `AppState.startSchedulers` 整体短路：不测速/不择优/不拉订阅/不碰 iCloud，
///     防止真实调度覆盖演示数据（演示节点的 host 都是假的，一测全挂）。
///
/// 与「示例数据已删」的纪律不冲突：那次删的是喂进**正常路径**的假连接流
/// （sampleConnectionsLoop），这里是显式参数才进的隔离模式，正常启动完全不可达。
@MainActor
enum ScreenshotDemoMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-qz-screenshot")
    }

    private static var requestedSection: AppSection? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-qz-tab"), args.indices.contains(i + 1) else { return nil }
        switch args[i + 1] {
        case "home": return .home
        case "nodes": return .nodes
        case "subscriptions": return .subscriptions
        case "rules": return .rules
        case "settings": return .settings
        default: return nil
        }
    }

    static func applyIfRequested(to state: AppState) {
        guard isActive else { return }

        let now = Date()
        let subID = UUID()
        state.subscriptions = [
            Subscription(
                id: subID,
                name: "云帆机场",
                url: URL(string: "https://airport.example.com/api/v1/subscribe?token=demo")!,
                lastUpdatedAt: now.addingTimeInterval(-3600),
                nodeCount: 10,
                usedBytes: 52_400_000_000,
                totalBytes: 200_000_000_000,
                expiresAt: now.addingTimeInterval(86_400 * 202)
            ),
        ]

        // 名字/地区/倍率/延迟都取真实订阅里常见的形态；经代理延迟只给一部分节点，
        // 和真实使用中「测过一轮直连、部分节点补测过经代理」的状态一致。
        func node(
            _ name: String, _ proto: ProxyProtocol, _ latency: Int,
            proxied: Int? = nil, peakDown: Int64? = nil
        ) -> Node {
            var n = Node(name: name, protocolType: proto, host: "demo.example.com", port: 443)
            n.password = "demo"
            n.uuid = UUID().uuidString
            n.lastLatencyMs = latency
            n.lastTestedAt = now.addingTimeInterval(-90)
            if let proxied {
                n.lastProxiedLatencyMs = proxied
                n.lastProxiedTestedAt = now.addingTimeInterval(-90)
            }
            if let peakDown {
                n.observedPeakDownBps = peakDown
                n.observedBandwidthAt = now.addingTimeInterval(-600)
            }
            n.subscriptionId = subID
            return n
        }
        let current = node("🇭🇰 香港 IEPL-01", .trojan, 32, proxied: 58, peakDown: 11_800_000)
        state.nodes = [
            current,
            node("🇭🇰 香港 BGP-02 | 0.5x", .shadowsocks, 41, proxied: 74),
            node("🇯🇵 东京 IIJ-01", .vless, 48, proxied: 83),
            node("🇯🇵 大阪 SoftBank", .vmess, 55),
            node("🇸🇬 新加坡 直连-01", .trojan, 62, proxied: 95),
            node("🇰🇷 首尔 KT-01", .vmess, 66),
            node("🇬🇧 伦敦 CN2-01", .vless, 71),
            node("🇺🇸 洛杉矶 GIA-01", .trojan, 128, proxied: 176),
            node("🇺🇸 圣何塞 CN2 | 2x", .vless, 142),
            node("🇩🇪 法兰克福-01", .shadowsocks, 185),
        ]
        state.currentNodeId = current.id

        state.customRules = [
            Rule(type: .domainSuffix, value: "openai.com", target: .proxy),
            Rule(type: .domainSuffix, value: "youtube.com", target: .proxy),
            Rule(type: .domainKeyword, value: "github", target: .proxy),
            Rule(type: .domainSuffix, value: "bilibili.com", target: .direct),
            Rule(type: .geoip, value: "CN", target: .direct),
        ]

        // 展示值：调度器已在 startSchedulers 整体短路，设置页显示「启动时+定时」只是观感，
        // 不会真跑（真跑会拿假 host 测速把演示延迟洗掉）。
        state.settings.autoSelectTrigger = .onAppLaunchAndInterval

        // 公网 IP 卡片：注入演示值。真实刷新会把本机真实出口 IP 截进 App Store 图（隐私）,
        // refreshPublicIPInfo 已在 demo 下短路。
        state.proxyIPInfo = PublicIPInfo(
            ip: "45.154.23.108", country: "Hong Kong", city: "Kwun Tong", isp: "IEPL Network Ltd."
        )
        state.directIPInfo = PublicIPInfo(
            ip: "101.87.164.52", country: "China", region: "Shanghai", city: "上海", isp: "China Telecom"
        )

        if let section = requestedSection {
            state.activeSection = section
        }

        // 「已连接 2 小时 47 分」+ 满窗波形：先回填 60 秒历史样本让波形一进来就是满的，
        // 再起每秒喂样本的循环维持「实时在跑」的观感（顺带重申 isVPNRunning，
        // 抵抗任何状态观察者把它翻回 false）。
        state.isVPNRunning = true
        state.connectedSince = now.addingTimeInterval(-(2 * 3600 + 47 * 60))
        var upTotal: Int64 = 156_000_000
        var downTotal: Int64 = 2_410_000_000
        func sample(at t: Date, phase: Double) -> TrafficStats {
            let down = Int64(3_200_000 + 4_100_000 * abs(sin(phase / 7)) + Double.random(in: 0...900_000))
            let up = Int64(310_000 + 190_000 * abs(sin(phase / 5)) + Double.random(in: 0...80_000))
            upTotal += up
            downTotal += down
            return TrafficStats(
                uploadBytes: upTotal, downloadBytes: downTotal,
                uploadSpeedBps: up, downloadSpeedBps: down,
                activeConnections: Int.random(in: 18...27), sampledAt: t
            )
        }
        for s in (0..<60).reversed() {
            state.trafficHistory.record(sample(at: now.addingTimeInterval(-Double(s)), phase: Double(60 - s)))
        }
        Task { @MainActor in
            var phase = 60.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                phase += 1
                state.isVPNRunning = true
                state.tunnelError = nil   // 任何真实隧道操作漏网报错 → 秒关，别脏了截图
                state.trafficHistory.record(sample(at: Date(), phase: phase))
            }
        }
    }
}
