import Foundation
import QingzhouCore
import QingzhouLogging

/// 一次完整测速运行的产物。
public struct SpeedTestReport: Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let results: [LatencyResult]

    public init(startedAt: Date, finishedAt: Date, results: [LatencyResult]) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.results = results
    }
}

/// 测速调度器：并发跑多个 target，汇总结果。
public actor SpeedTestRunner {
    private let prober: LatencyProber
    private let logger: Logger?

    public init(prober: LatencyProber = URLSessionLatencyProber(), logger: Logger? = nil) {
        self.prober = prober
        self.logger = logger
    }

    /// 并发探测一组 URL。`timeout` 单位秒。
    public func run(urls: [URL], timeout: TimeInterval = 5) async -> SpeedTestReport {
        let started = Date()
        logger?.info("Speed test started for \(urls.count) targets", category: "speedtest")

        let results = await withTaskGroup(of: LatencyResult.self) { group in
            for url in urls {
                group.addTask { [prober] in
                    await prober.probe(url, timeout: timeout)
                }
            }
            var collected: [LatencyResult] = []
            for await r in group { collected.append(r) }
            return collected
        }

        // 保持与传入顺序一致，便于 UI 渲染
        let indexed = Dictionary(uniqueKeysWithValues: results.map { ($0.url, $0) })
        let ordered = urls.compactMap { indexed[$0] }

        let finished = Date()
        let summary = ordered.map { "\($0.url.host ?? $0.url.absoluteString)=\($0.latencyMs.map(String.init) ?? "fail")" }.joined(separator: ", ")
        logger?.info("Speed test done in \(Int(finished.timeIntervalSince(started) * 1000))ms: \(summary)", category: "speedtest")
        return SpeedTestReport(startedAt: started, finishedAt: finished, results: ordered)
    }

    /// 便利方法：探测全部内置 target。
    public func runBuiltInTargets(timeout: TimeInterval = 5) async -> SpeedTestReport {
        await run(urls: SpeedTestTarget.allCases.map { $0.url }, timeout: timeout)
    }
}
