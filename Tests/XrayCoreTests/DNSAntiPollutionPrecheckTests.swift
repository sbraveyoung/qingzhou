import XCTest
import QingzhouCore
import QingzhouProtocols
import XrayConfig
@testable import XrayCore

/// DNS 第 3 档（防污染 / 治「DNS 绕代理」）的**真实性校验**：compose rule 模式 →
/// `XrayCore.testConfig` 让打包的 xray-core (v26.6.27) 亲口确认两件事拼对了、能构建：
///   ① DNS servers 里的 `https+local://` **DoH 加密上游**语法本版 xray 接受；
///   ② routing 的「公共 DNS(8.8.8.8/1.1.1.1/阿里) → direct」规则合法。
///
/// **这是改核心 DNS「不冒隧道起不来的险」的安全阀**：DoH local 若不被本版 xray 接受，
/// testConfig 会 throw、此测试红 → 必须回退 buildDNS 的 DoH（否则真机上 rule 模式配置
/// 构建失败 = xray 起不来 = 用户断网）。无网络依赖，testConfig 只验配置合法性、不拨号。
/// tunInterfaceName 用 "utun9"：预检路径无 TUN fd，xray 严格校验接口名（见 composer 注释）。
final class DNSAntiPollutionPrecheckTests: XCTestCase {

    private func ruleConfig() throws -> String {
        let node = try ProxyURLParser.parse(
            "hysteria2://letmein@hy.example.com:36500?sni=hy.example.com&insecure=1#dns-precheck")
        let outbounds = try NodeConverter.toOutboundsJSON(node)
        return try XrayConfigComposer.compose(
            outboundsJSON: outbounds,
            mode: .rule,
            tunInterfaceName: "utun9"
        )
    }

    /// 规则模式完整配置（含 DoH local 上游 + 公共 DNS→direct 规则）必须通过 xray 构建。
    /// 红 = 本版 xray 不吃 `https+local://` 或该路由规则 → 回退 DoH，别上机。
    /// datDir 指向内置 geo 数据目录：rule 模式路由引用 geoip:private/cn，xray 构建时要加载
    /// geoip.dat（否则报错卡在 routing、根本走不到 DNS 段，验不了 DoH）。
    func testRuleModeDNSConfigPassesXrayBuild() throws {
        let datDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/Tunnel-Shared/Resources").path
        XCTAssertNoThrow(try XrayCore.testConfig(configJSON: try ruleConfig(), datDir: datDir))
    }

    /// 结构断言：DoH 加密上游确实进了 servers（防某次重构悄悄丢掉加密上游、退回明文）。
    /// 用 "dns.google"（不含 `/`）匹配，避开 JSONSerialization 把 `/` 转义成 `\/` 的干扰。
    func testDoHLocalUpstreamPresent() throws {
        let config = try ruleConfig()
        // 诊断：打印 dns 段前 300 字，确认 DoH 实际形态（转义与否）
        if let r = config.range(of: "\"servers\"") {
            let end = config.index(r.lowerBound, offsetBy: 300, limitedBy: config.endIndex) ?? config.endIndex
            print("【DNS servers 段】\(config[r.lowerBound..<end])")
        }
        XCTAssertTrue(config.contains("dns.google") && config.contains("https+local"),
                      "DoH 加密上游(dns.google + https+local)应在 rule 模式 DNS servers 里")
    }

    /// 结构断言：公共 DNS→direct 规则里含 8.8.8.8（治「DNS 上游绕代理」的正修不能丢）。
    func testPublicDNSDirectRulePresent() throws {
        let config = try ruleConfig()
        XCTAssertTrue(config.contains("8.8.8.8"),
                      "公共 DNS 上游（8.8.8.8）应出现在配置里（DNS servers 兜底 + routing direct 规则）")
    }

    /// 诊断：原样 dump rule 模式的完整 routing.rules（每条一行）+ dns 段，
    /// 用事实核对 8.8.8.8 那条规则的位置/形式，而非靠猜。
    func testDumpRuleModeRoutingAndDNS() throws {
        let config = try ruleConfig()
        let data = config.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let routing = obj["routing"] as! [String: Any]
        let rules = routing["rules"] as! [[String: Any]]
        print("【domainStrategy】\(routing["domainStrategy"] ?? "nil")")
        print("【routing.rules 共 \(rules.count) 条】")
        for (i, r) in rules.enumerated() {
            let d = try JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])
            print("  [\(i)] \(String(data: d, encoding: .utf8)!)")
        }
        let dns = obj["dns"] as! [String: Any]
        let dnsData = try JSONSerialization.data(withJSONObject: dns, options: [.sortedKeys])
        print("【dns】\(String(data: dnsData, encoding: .utf8)!)")
    }
}
