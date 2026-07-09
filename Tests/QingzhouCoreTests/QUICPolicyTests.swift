import XCTest
@testable import QingzhouCore

/// QUIC 三档策略 → 有效阻断值 的纯逻辑（无 IO，全分支可测）。
/// 语义见 docs/QUIC.md「智能策略（auto + 实测探测）」。
final class QUICPolicyResolverTests: XCTestCase {

    // MARK: - .alwaysBlock：恒挡，不看协议 / 不看实测坏标记

    func testAlwaysBlockIgnoresProtocolAndBrokenFlag() {
        for proto in ProxyProtocol.allCases {
            for broken in [true, false] {
                XCTAssertTrue(
                    QUICPolicyResolver.shouldBlock(
                        policy: .alwaysBlock, protocolType: proto, knownBrokenOnThisNode: broken),
                    "alwaysBlock 应恒挡（proto=\(proto) broken=\(broken)）")
            }
        }
    }

    // MARK: - .neverBlock：恒放，不看协议 / 不看实测坏标记

    func testNeverBlockIgnoresProtocolAndBrokenFlag() {
        for proto in ProxyProtocol.allCases {
            for broken in [true, false] {
                XCTAssertFalse(
                    QUICPolicyResolver.shouldBlock(
                        policy: .neverBlock, protocolType: proto, knownBrokenOnThisNode: broken),
                    "neverBlock 应恒放（proto=\(proto) broken=\(broken)）")
            }
        }
    }

    // MARK: - .auto + hysteria2

    func testAutoHysteria2NotBrokenAllows() {
        // hysteria2 且未标记坏 → 放行（QUIC 型节点原生转发 UDP，理应能跑 h3）
        XCTAssertFalse(QUICPolicyResolver.shouldBlock(
            policy: .auto, protocolType: .hysteria2, knownBrokenOnThisNode: false))
    }

    func testAutoHysteria2BrokenBlocks() {
        // hysteria2 但已实测坏（该节点没转发 UDP）→ 挡，逼回退 TCP
        XCTAssertTrue(QUICPolicyResolver.shouldBlock(
            policy: .auto, protocolType: .hysteria2, knownBrokenOnThisNode: true))
    }

    // MARK: - .auto + 其余协议：一律挡（TCP 基节点 UDP 转发普遍差）

    func testAutoNonHysteria2AlwaysBlocks() {
        for proto in ProxyProtocol.allCases where proto != .hysteria2 {
            for broken in [true, false] {
                XCTAssertTrue(
                    QUICPolicyResolver.shouldBlock(
                        policy: .auto, protocolType: proto, knownBrokenOnThisNode: broken),
                    "auto 下非 hysteria2（\(proto)）应恒挡")
            }
        }
    }
}

/// HTTP/3 实测探测结果（协商到的传输协议名）→ 是否标记「该节点 QUIC 实测坏」的纯决策。
final class QUICProbeDecisionTests: XCTestCase {

    func testH3KeepsAllowed() {
        // 真走上了 h3 → UDP 转发可用，不标记坏
        XCTAssertFalse(QUICProbeDecision.shouldMarkBroken(networkProtocolName: "h3"))
    }

    func testFallbackProtocolsMarkBroken() {
        // 回退到 h2 / http/1.1（说明 h3 没握上手 → 节点没转发 UDP）→ 标记坏
        for proto in ["h2", "http/1.1", "spdy/3.1", ""] {
            XCTAssertTrue(
                QUICProbeDecision.shouldMarkBroken(networkProtocolName: proto),
                "非 h3（\(proto)）应标记坏")
        }
    }

    func testNilProtocolMarksBroken() {
        // 请求整体失败 / 拿不到 metrics → 视作坏（保守回退 TCP）
        XCTAssertTrue(QUICProbeDecision.shouldMarkBroken(networkProtocolName: nil))
    }
}
