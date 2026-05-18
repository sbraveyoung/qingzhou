import Foundation
import VPNCore

public enum RuleParseError: Error, Equatable, Sendable {
    case empty
    case missingFields(String)
    case unknownType(String)
    case unknownTarget(String)
    case invalidValue(String)
}

/// 把规则源文本解析成结构化规则。
///
/// 支持单行格式：
/// - `DOMAIN-SUFFIX,google.com,PROXY`
/// - `IP-CIDR,10.0.0.0/8,DIRECT,no-resolve`（第 4 个字段当作 flag 存在 comment）
/// - `FINAL,PROXY`
/// - `# 注释` / 空行 → 跳过
public enum RuleParser {
    /// 解析整段文本，返回有效规则；错误行收集起来不致命。
    public static func parseAll(_ text: String) -> (rules: [Rule], errors: [(line: String, error: Error)]) {
        var rules: [Rule] = []
        var errors: [(String, Error)] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            do {
                rules.append(try parseLine(line))
            } catch {
                errors.append((line, error))
            }
        }
        return (rules, errors)
    }

    public static func parseLine(_ line: String) throws -> Rule {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !parts.isEmpty else { throw RuleParseError.empty }

        let typeRaw = parts[0].uppercased()
        guard let type = RuleType(rawValue: typeRaw) else {
            throw RuleParseError.unknownType(typeRaw)
        }

        // FINAL 是特例：FINAL,PROXY
        if type == .final {
            guard parts.count >= 2 else { throw RuleParseError.missingFields(line) }
            guard let target = RuleTarget(rawValue: parts[1].uppercased()) else {
                throw RuleParseError.unknownTarget(parts[1])
            }
            return Rule(type: .final, value: "", target: target)
        }

        guard parts.count >= 3 else { throw RuleParseError.missingFields(line) }
        let value = parts[1]
        guard let target = RuleTarget(rawValue: parts[2].uppercased()) else {
            throw RuleParseError.unknownTarget(parts[2])
        }
        let comment = parts.count >= 4 ? parts[3...].joined(separator: ",") : nil

        // 对 IP-CIDR / IP-CIDR6 做轻量校验
        switch type {
        case .ipCIDR:
            guard CIDR.parseIPv4(value) != nil else { throw RuleParseError.invalidValue(value) }
        case .ipCIDR6:
            guard CIDR.parseIPv6(value) != nil else { throw RuleParseError.invalidValue(value) }
        default:
            break
        }

        return Rule(type: type, value: value, target: target, comment: comment)
    }
}
