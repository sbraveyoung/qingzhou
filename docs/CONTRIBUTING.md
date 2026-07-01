# 贡献指南

## 提交前清单

```bash
swift build              # 必须通过
swift test               # 必须 73 项全过（新增功能要加新测试）
xcodebuild -scheme Qingzhou-Package -destination 'generic/platform=iOS' build  # iOS 也要过
```

## 代码风格

- 跟随 Swift API Design Guidelines。
- 4 空格缩进；最大行宽 120。
- 注释解释 **为什么**，不解释 **是什么**（命名好的代码不需要后者）。
- 写 `// TODO` 时同时附上 issue 链接，不写「以后再说」。

## 模块边界

加新功能前先确认放在哪个模块：

| 类型 | 放在 |
|---|---|
| 新协议（比如 ShadowTLS） | `QingzhouProtocols` |
| 新规则类型 | `QingzhouRules` + `QingzhouCore.Rule` |
| 新测速目标 | `QingzhouSpeedTest.SpeedTestTarget` |
| 新 UI 视图 | `QingzhouApp` |
| 新模型字段 | `QingzhouCore`（其他模块都不应该有自己的领域模型） |

底层模块（QingzhouCore）**不能**依赖上层。如果你发现需要这么做，多半是抽象错位 —— 先讨论。

## 加新协议解析器

1. 在 `QingzhouCore/ProxyProtocol.swift` 注册新的 case + scheme。
2. 在 `QingzhouProtocols/` 新建 `<Name>Parser.swift`，实现 `static func parse(_:) throws -> Node`。
3. 在 `QingzhouProtocols/ProxyURLParser.swift` 的 switch 里加分发。
4. 在 `Tests/QingzhouProtocolsTests/` 写至少 3 个测试：正常路径、缺字段错误、特殊字符 / URL-decode。

## 加新规则类型

1. `QingzhouCore/Rule.swift` 加 `RuleType` case。
2. `QingzhouRules/RuleEngine.swift` 在 `match` 的 switch 里加分支；如果需要预编译（像 CIDR）那样，加到 `init` 里。
3. `Tests/QingzhouRulesTests/` 加测试覆盖 hit / miss / 边界。

## PR 模板（建议）

```
## Why
<这个变更解决了什么问题>

## What
<改了哪些文件、增加了哪些 API>

## Test
- [ ] swift build
- [ ] swift test（X 项通过，新增 Y 项）
- [ ] xcodebuild iOS
- [ ] 手动验证（如适用）
```

## Issue 标签

- `bug`：行为偏离预期。
- `enhancement`：新功能。
- `protocol:<名字>`：协议解析相关。
- `phase:2`：阶段 2 才会处理（涉及 NetworkExtension / xray-core / libXray）。
- `good first issue`：欢迎新人。
