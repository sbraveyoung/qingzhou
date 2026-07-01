import Foundation
import QingzhouCore

/// 日志级别。`all` 仅作过滤用，不用于实际写入。
public enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case all = "ALL"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    private var rank: Int {
        switch self {
        case .all:   return 0
        case .debug: return 1
        case .info:  return 2
        case .warn:  return 3
        case .error: return 4
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct LogEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// 内存环形缓冲 + 可选文件落盘的日志器。线程安全。
///
/// 设计选择：
/// - 用 `NSLock` 而不是 actor，因为 logger 经常被同步上下文调用（包括 PacketTunnel 的 packet 回调），
///   `await` 会导致调用方都被传染成 async，得不偿失。
/// - 环形容量默认 5000 条，超过则丢弃最老的条目。这是 UI 展示用的；如需归档要走文件 sink。
public final class Logger: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [LogEntry]
    private let capacity: Int
    private var minimumLevel: LogLevel
    private var fileSink: FileSink?
    private var subscribers: [UUID: @Sendable (LogEntry) -> Void] = [:]

    public init(capacity: Int = 5000, minimumLevel: LogLevel = .info) {
        self.capacity = capacity
        self.minimumLevel = minimumLevel
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    public func setMinimumLevel(_ level: LogLevel) {
        lock.lock(); defer { lock.unlock() }
        minimumLevel = level
    }

    public func enableFileSink(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        fileSink = try FileSink(url: url)
    }

    public func disableFileSink() {
        lock.lock(); defer { lock.unlock() }
        fileSink = nil
    }

    /// 订阅新日志事件；返回取消令牌。订阅回调在调用 log 的线程上同步执行，回调内勿做重活。
    @discardableResult
    public func subscribe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID()
        subscribers[token] = handler
        return token
    }

    public func unsubscribe(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        subscribers.removeValue(forKey: token)
    }

    public func log(_ level: LogLevel, category: String = "app", _ message: @autoclosure () -> String) {
        // 先评估级别，避免不必要的字符串构造
        lock.lock()
        guard level >= minimumLevel else { lock.unlock(); return }
        let entry = LogEntry(level: level, category: category, message: message())
        if buffer.count >= capacity {
            buffer.removeFirst(buffer.count - capacity + 1)
        }
        buffer.append(entry)
        let sink = fileSink
        let subs = subscribers.values
        lock.unlock()

        sink?.write(entry)
        for cb in subs { cb(entry) }
    }

    public func debug(_ message: @autoclosure () -> String, category: String = "app") {
        log(.debug, category: category, message())
    }
    public func info(_ message: @autoclosure () -> String, category: String = "app") {
        log(.info, category: category, message())
    }
    public func warn(_ message: @autoclosure () -> String, category: String = "app") {
        log(.warn, category: category, message())
    }
    public func error(_ message: @autoclosure () -> String, category: String = "app") {
        log(.error, category: category, message())
    }

    public func snapshot() -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }

    /// 按级别过滤 + 关键字搜索（不区分大小写）。
    public func search(level: LogLevel = .all, keyword: String = "") -> [LogEntry] {
        let entries = snapshot()
        let kw = keyword.lowercased()
        return entries.filter { entry in
            let levelOK = level == .all || entry.level >= level
            let keywordOK = kw.isEmpty
                || entry.message.lowercased().contains(kw)
                || entry.category.lowercased().contains(kw)
            return levelOK && keywordOK
        }
    }
}

/// 简易文件 sink。每条日志一行，UTF-8。
final class FileSink {
    private let handle: FileHandle
    private let formatter: ISO8601DateFormatter

    init(url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        self.handle = try FileHandle(forWritingTo: url)
        try self.handle.seekToEnd()
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    deinit {
        try? handle.close()
    }

    func write(_ entry: LogEntry) {
        let line = "\(formatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)\n"
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
}
