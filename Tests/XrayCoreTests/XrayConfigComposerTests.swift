import XCTest
import VPNCore
@testable import XrayCore

final class XrayConfigComposerTests: XCTestCase {

    /// libXray 出来的 trojan outbound 形态（用真实的链接通过 XrayCore 转一次拿到）。
    private func realTrojanOutbounds() throws -> String {
        let link = "trojan://pw@example.com:443?sni=example.com#hk"
        return try XrayCore.convertShareLinks(link)
    }

    // MARK: - 结构性测试（不依赖 xray-core 启动）

    func testComposeWrapsOutboundIntoFullConfigGlobal() throws {
        let outbounds = try realTrojanOutbounds()
        let composed = try XrayConfigComposer.compose(outboundsJSON: outbounds, mode: .global)

        let json = try parse(composed)
        // 顶层 key
        XCTAssertNotNil(json["inbounds"])
        XCTAssertNotNil(json["outbounds"])
        XCTAssertNotNil(json["routing"])
        XCTAssertNotNil(json["dns"])
        XCTAssertNotNil(json["log"])

        // tun inbound 存在
        let inbounds = json["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.count, 1)
        XCTAssertEqual(inbounds[0]["protocol"] as? String, "tun")

        // outbounds 至少 3 个：proxy / direct / reject
        let outs = json["outbounds"] as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(outs.count, 3)
        let tags = outs.compactMap { $0["tag"] as? String }
        XCTAssertTrue(tags.contains("proxy"))
        XCTAssertTrue(tags.contains("direct"))
        XCTAssertTrue(tags.contains("reject"))

        // proxy 是 trojan
        let proxy = outs.first(where: { $0["tag"] as? String == "proxy" })!
        XCTAssertEqual(proxy["protocol"] as? String, "trojan")
    }

    func testRoutingRulesGlobalSendsAllToProxy() throws {
        let outbounds = try realTrojanOutbounds()
        let json = try parse(try XrayConfigComposer.compose(outboundsJSON: outbounds, mode: .global))
        let rules = (json["routing"] as! [String: Any])["rules"] as! [[String: Any]]
        // 最后一条 catch-all 必须指向 proxy
        let last = rules.last!
        XCTAssertEqual(last["outboundTag"] as? String, "proxy")
        // 至少有一条 RFC1918 / loopback CIDR 标为 direct（不依赖 geoip）
        XCTAssertTrue(rules.contains { r in
            (r["outboundTag"] as? String) == "direct" &&
            ((r["ip"] as? [String])?.contains("10.0.0.0/8") ?? false)
        })
    }

    func testRoutingRulesRuleModeIncludesGeositeCn() throws {
        let outbounds = try realTrojanOutbounds()
        let json = try parse(try XrayConfigComposer.compose(outboundsJSON: outbounds, mode: .rule))
        let rules = (json["routing"] as! [String: Any])["rules"] as! [[String: Any]]
        // 应当包含 geosite:cn → direct
        XCTAssertTrue(rules.contains { r in
            (r["outboundTag"] as? String) == "direct" &&
            ((r["domain"] as? [String])?.contains("geosite:cn") ?? false)
        })
        // 应当包含 geoip:cn → direct
        XCTAssertTrue(rules.contains { r in
            (r["outboundTag"] as? String) == "direct" &&
            ((r["ip"] as? [String])?.contains("geoip:cn") ?? false)
        })
    }

    func testRoutingRulesDirectModeSendsAllToDirect() throws {
        let outbounds = try realTrojanOutbounds()
        let json = try parse(try XrayConfigComposer.compose(outboundsJSON: outbounds, mode: .direct))
        let rules = (json["routing"] as! [String: Any])["rules"] as! [[String: Any]]
        for r in rules {
            XCTAssertEqual(r["outboundTag"] as? String, "direct")
        }
    }

    func testDNSGlobalUsesPublicServers() throws {
        let outbounds = try realTrojanOutbounds()
        let json = try parse(try XrayConfigComposer.compose(outboundsJSON: outbounds, mode: .global))
        let dns = json["dns"] as! [String: Any]
        let servers = dns["servers"] as! [Any]
        // 第一个应当是 8.8.8.8 字符串
        XCTAssertEqual(servers.first as? String, "8.8.8.8")
        XCTAssertEqual(dns["queryStrategy"] as? String, "UseIP")
    }

    func testDNSRuleModeIncludesChinaDNS() throws {
        let outbounds = try realTrojanOutbounds()
        let json = try parse(try XrayConfigComposer.compose(outboundsJSON: outbounds, mode: .rule))
        let dns = json["dns"] as! [String: Any]
        let servers = dns["servers"] as! [Any]
        // 至少一项是字典且 address = 223.5.5.5
        let alidns = servers.first { entry in
            (entry as? [String: Any])?["address"] as? String == "223.5.5.5"
        }
        XCTAssertNotNil(alidns)
    }

    // MARK: - 各协议都能跑通 compose

    func testComposeVMess() throws {
        let json = #"""
        {"v":"2","ps":"vmess1","add":"v.example.com","port":"443","id":"11111111-2222-3333-4444-555555555555","aid":0,"scy":"auto","net":"ws","path":"/","tls":"tls"}
        """#
        let link = "vmess://" + Data(json.utf8).base64EncodedString()
        let out = try XrayCore.convertShareLinks(link)
        let composed = try XrayConfigComposer.compose(outboundsJSON: out, mode: .global)
        XCTAssertTrue(composed.contains("\"protocol\":\"vmess\"") || composed.contains("vmess"))
    }

    func testComposeShadowsocks() throws {
        let link = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@s.example.com:8388#ss-test"
        let out = try XrayCore.convertShareLinks(link)
        let composed = try XrayConfigComposer.compose(outboundsJSON: out, mode: .rule)
        XCTAssertTrue(composed.contains("shadowsocks") || composed.contains("ss"))
    }

    func testComposeVLESS() throws {
        let link = "vless://abcd-1234@vl.example.com:443?encryption=none&security=tls&type=ws#vl"
        let out = try XrayCore.convertShareLinks(link)
        let composed = try XrayConfigComposer.compose(outboundsJSON: out, mode: .global)
        XCTAssertTrue(composed.contains("vless"))
    }

    // MARK: - 防御性清理 libXray 错填字段

    /// libXray 在某些 share link 上会把节点显示名塞进 outbound.sendThrough。
    /// sendThrough 本意是本地绑定 IP，xray-core 当 net.IP 解析必失败 →
    /// "unable to send through: <node 名>"。compose 必须主动剔除。
    func testComposeStripsSendThroughFromAllOutbounds() throws {
        let fakeOutboundsJSON = #"""
        {
          "outbounds": [
            {
              "tag": "whatever",
              "protocol": "trojan",
              "sendThrough": "日本-TY-2-流量倍率:1.0",
              "settings": {
                "servers": [{"address": "example.com", "port": 443, "password": "pw"}]
              }
            }
          ]
        }
        """#
        let composed = try XrayConfigComposer.compose(outboundsJSON: fakeOutboundsJSON, mode: .global)
        let json = try parse(composed)
        let outs = json["outbounds"] as! [[String: Any]]
        for out in outs {
            XCTAssertNil(out["sendThrough"],
                         "sendThrough 必须从所有 outbound 上剔除，否则 xray-core 启动会失败")
        }
    }

    // MARK: - 错误路径

    func testComposeRejectsInvalidJSON() {
        XCTAssertThrowsError(
            try XrayConfigComposer.compose(outboundsJSON: "not json", mode: .global)
        )
    }

    func testComposeRejectsEmptyOutbounds() {
        XCTAssertThrowsError(
            try XrayConfigComposer.compose(outboundsJSON: #"{"outbounds":[]}"#, mode: .global)
        )
    }

    // MARK: - helpers

    private func parse(_ s: String) throws -> [String: Any] {
        let data = s.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
