// macOS 内容过滤扩展（NEFilterDataProvider）—— 唯一目的：给每条连接标注「是哪个 App 发起的」。
//
// 为什么需要它：packet-tunnel 在 TUN 层只看到 IP 包，拿不到进程归属。而 content filter 的
// NEFilterFlow 提供 sourceAppIdentifier（bundle id）。我们**只观测、一律放行**（.allow()），
// 把「源端口 → bundle id」写进 App Group；主 App 用 access log 里的源端口反查出是哪个 App。
//
// 注意：`content-filter-provider` entitlement 需 Apple 特批；启用要用户在系统里授权。

import NetworkExtension
import os.log

final class FilterDataProvider: NEFilterDataProvider {
    private let log = OSLog(subsystem: "com.sbraveyoung.qingzhou.filter", category: "Filter")

    /// 源端口 → bundle id。handleNewFlow 高频、跨线程，用 unfair lock 保护；定时 flush 到 App Group。
    private let portToApp = OSAllocatedUnfairLock(initialState: [String: String]())
    private var flushTimer: DispatchSourceTimer?
    private let flushQueue = DispatchQueue(label: "com.sbraveyoung.qingzhou.filter.flush")

    private static let groupID = "group.com.sbraveyoung.qingzhou"
    private static var mapURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("source-apps.json")
    }

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        os_log("startFilter", log: log, type: .default)
        let timer = DispatchSource.makeTimerSource(queue: flushQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        flushTimer = timer
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        flushTimer?.cancel()
        flushTimer = nil
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        if let socketFlow = flow as? NEFilterSocketFlow,
           let bundleID = flow.sourceAppIdentifier,          // App 的 bundle id / 签名标识
           let port = localPort(of: socketFlow) {
            portToApp.withLock { $0[port] = bundleID }
        }
        return .allow()                                       // 只观测，绝不阻断
    }

    /// 取 flow 本地端点的端口（App 建立连接时分配的源端口，与 access log 的 sourceAddress 端口一致）。
    private func localPort(of flow: NEFilterSocketFlow) -> String? {
        guard let endpoint = flow.localEndpoint as? NWHostEndpoint else { return nil }
        return endpoint.port                                  // NWHostEndpoint.port 是 String
    }

    private func flush() {
        let map = portToApp.withLock { $0 }
        guard !map.isEmpty, let url = Self.mapURL,
              let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
