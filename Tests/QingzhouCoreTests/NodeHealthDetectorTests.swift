import XCTest
@testable import QingzhouCore

/// NodeHealthDetector 的红队规格测试（docs/FAILOVER.md「NodeHealthDetector 纯逻辑规格」）。
///
/// 采样步长统一用 2 秒（扩展 reportXrayOutboundStats 的真实节流 ≈2s）。counters 是**累计**值。
/// 每条 spec 对应一个用例，注释里标了对应的红队失败模式（F#）。
final class NodeHealthDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_752_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - ① 持续「有上行无下行」→ suspect（F4/F19 配对判据 + 持续）

    func testSustainedUplinkNoDownlink_becomesSuspect() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        // 每 2s 上行涨 2000 B（=1000 B/s，> uplinkActiveBytesPerSec），下行恒 0。
        // baseline 在 t0；grace=6s，判定钟从 grace 结束（t0+6）才起。
        // 因此 suspect 应在 t0+6 + suspectSustainSeconds(10) ≈ t0+16 落定。
        var last: NodeHealth = .healthy
        for i in 0...9 {
            up += (i == 0 ? 0 : 2000)   // 第一条是 baseline，无增量
            last = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
            if Double(i) * 2 <= 12 {
                XCTAssertEqual(last, .healthy, "t0+\(Int(Double(i)*2)) 内不应判定（grace + 持续未满）")
            }
        }
        // 到 t0+18 时持续「上行涨、下行 0」已远超 grace+sustain → suspect
        XCTAssertEqual(last, .suspect)
        XCTAssertEqual(d.state, .suspect)
    }

    // MARK: - ② 空闲（上下行都 ≈0）→ healthy（F19）

    func testIdle_staysHealthy() {
        var d = NodeHealthDetector()
        // 上下行都不动：是空闲不是死。无论多久都 healthy。
        for i in 0...15 {
            let v = d.ingest(proxyUplinkTotal: 0, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
            XCTAssertEqual(v, .healthy, "空闲永远 healthy（t0+\(Int(Double(i)*2))）")
        }
    }

    // MARK: - ③ 大文件上传（上行猛、下行少但 >0 且有 ACK 回流）→ healthy

    func testHeavyUploadWithAckDownlink_staysHealthy() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        var down: Int64 = 0
        // 上行每 2s 涨 500KB（猛），下行每 2s 涨 4KB（=2000 B/s > downlinkFlatBytesPerSec，
        // 即 ACK 回流「有下行」）→ 配对不成立 → healthy。
        for i in 0...12 {
            up += (i == 0 ? 0 : 500_000)
            down += (i == 0 ? 0 : 4000)
            let v = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: down, at: at(Double(i) * 2))
            XCTAssertEqual(v, .healthy, "大上传但下行有回流 → healthy（t0+\(Int(Double(i)*2))）")
        }
    }

    // MARK: - ④ 单窗抖动 → 不 suspect（F3 去抖）

    func testSingleWindowBlip_doesNotSuspect() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        var down: Int64 = 0
        // grace 之外，交替：一个「坏窗」（上行涨、下行 0）后立刻一个「healthy-active 窗」
        // （下行回流）。任一坏窗都不连续满 10s → 永不 suspect。
        for i in 0...15 {
            let bad = (i % 2 == 1)
            up += (i == 0 ? 0 : 4000)
            down += (i == 0 ? 0 : (bad ? 0 : 4000))
            let v = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: down, at: at(Double(i) * 2))
            XCTAssertEqual(v, .healthy, "单窗抖动不该 suspect（t0+\(Int(Double(i)*2))）")
        }
    }

    // MARK: - ⑤ baseline 重置后判定空窗 + 作废旧累计（F5）

    func testResetBaseline_discardsAccumulationAndBlanks() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        // 先攒一段坏窗（到 t0+12，接近但未到 suspect —— suspect 本会在 t0+14 落定）
        for i in 0...6 {
            up += (i == 0 ? 0 : 2000)
            _ = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
        }
        XCTAssertEqual(d.state, .healthy, "t0+12 应尚未 suspect")

        // switch/restart：作废旧 baseline，进入判定空窗
        d.resetBaseline()

        // 重置后继续坏窗：必须重新走完 grace + sustain 才可能 suspect。
        // t0+14 建新 baseline；若不作废旧累计，t0+14 本该立刻 suspect —— 这里必须仍 healthy。
        var last: NodeHealth = .healthy
        for i in 7...11 {   // t0+14 … t0+22
            up += 2000
            last = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
        }
        XCTAssertEqual(last, .healthy, "baseline 重置后累计作废，短时间内不应 suspect")
    }

    // MARK: - ⑥ grace 窗内不判（F7 起手宽限）

    func testGraceWindow_noSuspectDuringGrace() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        // 从 t0 起就连续坏窗。若无 grace，判定钟从首个间隔起，t0+10 就该 suspect。
        // 有 graceSeconds(6) → 判定钟推迟到 grace 结束，t0+12（已 >10s 连续坏）仍应 healthy。
        var vAt12: NodeHealth = .healthy
        for i in 0...6 {   // t0 … t0+12
            up += (i == 0 ? 0 : 3000)
            let v = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
            if i == 6 { vAt12 = v }
        }
        XCTAssertEqual(vAt12, .healthy, "grace 把判定钟往后推：t0+12 已 >10s 连续坏但仍不判")
    }

    // MARK: - ⑦ 样本间隔巨跳（挂起/睡眠）→ 丢弃该窗、重建 baseline（F8）

    func testSuspendGap_discardsWindowAndRebuilds() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        // 先攒坏窗到接近 suspect（t0+12, healthy —— 再走一窗就会 suspect）
        for i in 0...6 {
            up += (i == 0 ? 0 : 2000)
            _ = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
        }
        XCTAssertEqual(d.state, .healthy)

        // 设备睡了 100s（dt=100 > maxSampleGapSeconds=8）：这一窗必须丢弃、重建 baseline，
        // 期间上行累计巨涨（睡前排队的字节）也不得算数。
        up += 5_000_000
        let vGap = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(114))
        XCTAssertEqual(vGap, .healthy, "睡眠跳变窗必须丢弃，不能被巨大上行增量误触发")

        // 醒来后继续坏窗：累计已作废 + 重新宽限，短时间内不应 suspect
        var last: NodeHealth = .healthy
        for i in 0...3 {   // t0+116 … t0+122
            up += 2000
            last = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(116 + Double(i) * 2))
        }
        XCTAssertEqual(last, .healthy, "睡眠后重建 baseline，需重新走完 grace+sustain")
    }

    // MARK: - ⑧ direct 模式无上行 → no-op（模式感知，F19 规则变体）

    func testDirectModeNoUplink_isNoOp() {
        var d = NodeHealthDetector()
        // 全直连 / 规则全走 direct：proxy outbound 计数几乎不动（上行 ≈0）。
        // 即便下行也是 0，也只是「proxy 没在用」→ 永远 healthy，绝不 suspect。
        for i in 0...15 {
            let v = d.ingest(proxyUplinkTotal: 0, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
            XCTAssertEqual(v, .healthy, "proxy 无上行 → no-op（t0+\(Int(Double(i)*2))）")
        }
    }

    // MARK: - ⑨ 计数器回退（xray 重启归零）→ 重建 baseline（F5 变体）

    func testCounterReset_rebuildsBaseline() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        for i in 0...6 {
            up += (i == 0 ? 0 : 2000)
            _ = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
        }
        XCTAssertEqual(d.state, .healthy)
        // xray 重启：计数器归零（当前累计 < 上一条）→ 视为重建 baseline，累计作废。
        var last: NodeHealth = .healthy
        var up2: Int64 = 0
        for i in 7...11 {
            up2 += 2000
            last = d.ingest(proxyUplinkTotal: up2, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
        }
        XCTAssertEqual(last, .healthy, "计数器归零后重建 baseline，短时间内不应 suspect")
    }

    // MARK: - ⑩ 真死透了会 suspect（正向对照：重置后走完完整窗口确实会判）

    func testEventuallySuspectsAfterFullWindow() {
        var d = NodeHealthDetector()
        var up: Int64 = 0
        var last: NodeHealth = .healthy
        for i in 0...15 {   // 一路坏到 t0+30，远超 grace+sustain
            up += (i == 0 ? 0 : 2000)
            last = d.ingest(proxyUplinkTotal: up, proxyDownlinkTotal: 0, at: at(Double(i) * 2))
        }
        XCTAssertEqual(last, .suspect, "持续坏满整窗后必须 suspect")
    }
}
