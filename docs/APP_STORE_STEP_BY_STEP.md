# 轻舟 · App Store 上架 · 手把手指引

> 组织版 Apple Developer 账号已就位（2026-07-03）。这份是**逐步操作**清单，按顺序做，
> 每步标了「谁做」（👤=你手动 / 🤖=Claude 能代劳，喊我）。元数据文案见
> [APP_STORE.md](APP_STORE.md) §3；隐私政策见 [PRIVACY.md](PRIVACY.md)；上架前功能验收见
> [ACCEPTANCE.md](ACCEPTANCE.md)。

## ⚡ 实况更新（2026-07-06，登录 Dev Portal / ASC 实查）

- **账号是「原地转换」成组织的，Team ID 没变，仍是 `UK7MME38H9`**（Membership 页实查：
  注册身份=组织，法人 Beijing Xiangshui Zhouxing Technology Co., Ltd.）。
  → **阶段 0.4 和阶段 1 整个免做**：`project.yml` 的 `DEVELOPMENT_TEAM` 本来就对，
  identifiers / App Group / iCloud 容器 / profile 全部继续有效。
- **阶段 3 已完成**：ASC 记录「轻舟 Qingzhou」已建（Apple ID 6787037928），版本 1.0 状态「准备提交」。
- **阶段 7 走到一半**：build **1.0 (2)** 已上传并处理完成，内部测试群组已建、
  内部测试员 sbraveyoung@gmail.com 已加；**还没人安装测试**（邀请/安装数全是 0）。
- ⚠️ **新发现（ASC 横幅）**：欧盟《数字服务法》(DSA) 要求先提供**交易商状态**才能向
  欧盟地区提交 —— 要么在 ASC「商务」里填交易商信息，要么上架地区**不勾欧盟**（更省事）。
- 剩余主线：👤 手机装 TestFlight build 自测 → 👤+🤖 截图 → 👤 填元数据/隐私/合规/审核备注
  （文案我都备好了，见 APP_STORE.md §3/§5）→ 内测 1 周 → 提审。
>
> **术语**：ASC = App Store Connect（appstoreconnect.apple.com）；
> Dev Portal = developer.apple.com/account（证书、Identifiers、Profiles）。

---

## 阶段 0 · 账号与团队确认（10 分钟）

**0.1** 👤 用组织账号登录 [ASC](https://appstoreconnect.apple.com)，右上角确认当前团队是**组织**（不是你的个人 team）。
**0.2** 👤 「用户与访问」里确认你是 **Account Holder 或 Admin**（建 App、传包、提审都要 Admin+）。
**0.3** 👤 Xcode → Settings → Accounts → 加/确认这个组织 Apple ID 已登录，能看到组织 team。
**0.4** 🤖 我把 `Apps/project.yml` 里 5 处 `DEVELOPMENT_TEAM` 从个人 team `UK7MME38H9` 改成组织 team ID（你把组织 Team ID 发我，在 Dev Portal 右上角「Membership」能看到）。

---

## 阶段 1 · Identifiers / Capabilities（在组织 team 下重建，30–60 分钟）

> ⚠️ **关键坑**：Bundle ID、App Group、iCloud 容器**全局唯一**，可能已被你个人账号占用。
> 组织账号看不到个人账号注册的 ID。若报「already registered / taken」，先去个人账号
> Dev Portal 把旧的删掉（或改名），再在组织下建。**这一步不理顺，签名会一直失败。**

**1.1** 👤 [Dev Portal → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → 新建 **App IDs**（Explicit），共 5 个：

| Bundle ID | 用途 | 必开的 Capabilities |
|---|---|---|
| `com.sbraveyoung.qingzhou.ios` | 主 App | App Groups、Network Extensions、iCloud（含 CloudKit/Documents） |
| `com.sbraveyoung.qingzhou.ios.tunnel` | 隧道扩展 | App Groups、Network Extensions |
| `com.sbraveyoung.qingzhou.ios.widget` | 小组件 | App Groups、Network Extensions |
| `com.sbraveyoung.qingzhou.mac` | macOS 主 App | 同 iOS 主 App + System Extension（若上 MAS 再议） |
| `com.sbraveyoung.qingzhou.mac.tunnel` / `.widget` / `.filter` | macOS 扩展 | 对应能力 |

**1.2** 👤 [Identifiers → App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) → 新建 `group.com.sbraveyoung.qingzhou`。回到**每个** App ID 的 App Groups capability，勾上这个 group。
**1.3** 👤 [Identifiers → iCloud Containers](https://developer.apple.com/account/resources/identifiers/list/cloudContainer) → 新建 `iCloud.com.sbraveyoung.qingzhou`。在两个主 App ID 的 iCloud capability 里勾上它。（**别漏 iCloud——轻舟的配置备份依赖它**。）
**1.4** 👤 Network Extensions：iOS 是自助勾选即可；确认 5 个 ID 里该开的都开了。

> 提示：以上 👤 步骤我给不了你点，但每一项对应 `Apps/project.yml` 里已经写好的 entitlements
> （App Group / networkextension / iCloud 容器都在）。你在网页勾的 capability 必须和
> project.yml 里声明的一一对应，否则 Xcode 自动签名会报 entitlement 不匹配。

---

## 阶段 2 · 构建与签名（我代劳大部分）

**2.1** 🤖 我改好 `DEVELOPMENT_TEAM` 后 `xcodegen generate`，用组织 team + `-allowProvisioningUpdates`
本地 Archive 一次，确认自动签名能在组织 team 下生成 profile（首次可能要你在 Xcode 弹窗点一下信任）。
**2.2** 🤖 Release 构建卫生：日志级别降到 warn、确认 DEBUG 钩子（`--qz-*` 那些）不编进 Release、跑一遍杀进程重开不崩。
**2.3** 🤖 确认 1024 图标无 alpha（已压平）、各尺寸 asset 齐全。

---

## 阶段 3 · ASC 建 App（15 分钟，你来）

> ⚠️ **iOS 和 macOS 必须各自建独立 App 记录，不能勾在同一个里。** ASC 的「一个 App 记录
> 多平台」（勾 iOS + macOS）要求**两个平台用同一个 Bundle ID**；而轻舟 iOS 是
> `com.sbraveyoung.qingzhou.ios`、macOS 是 `com.sbraveyoung.qingzhou.mac`，**Bundle ID 不同**，
> 所以只能分开建。现在**只建 iOS、只勾 iOS 平台**；macOS 以后单独建一条记录（且 macOS 的
> content filter 系统扩展在 MAS 的分发路径要单独查，本就该晚一版）。
> （想让两平台共用一条记录/共享评分，得把 macOS 也改成同一个 Bundle ID —— 那是一次不小的
> 重构，扩展/entitlement/App Group 全要重来，不值当，保持分开即可。）

**3.1** 👤 [ASC → Apps → +（新建 App）](https://appstoreconnect.apple.com/apps)：
- 平台：**只勾 iOS**（macOS 以后单独建记录，见上方警告）
- 名称：**轻舟 Qingzhou**（「轻舟」已被占，见 APP_STORE.md §3.1 候选序列；桌面显示名仍是「轻舟」不受影响）
- 主要语言：**简体中文**
- Bundle ID：选 `com.sbraveyoung.qingzhou.ios`
- SKU：随便一个唯一串，如 `qingzhou-ios-001`
- 用户访问权限：完全访问

**3.2** 👤 建好后进入 App，左侧「App 信息」：
- 类别：**工具（Utilities）**（副类别可留空）
- 内容版权：自持（用了 MIT/MPL 开源，无第三方版权）

---

## 阶段 4 · 元数据 + 隐私 + 合规（30 分钟，你填我给料）

**4.1** 👤 「App 隐私」→ 按 [APP_STORE.md §5](APP_STORE.md) 全填 **No**（零收集）。隐私政策 URL 填 GitHub Pages 的 PRIVACY 链接（见阶段 6）。
**4.2** 👤 版本信息页：
- 副标题、关键词、描述、What's New：直接抄 [APP_STORE.md §3](APP_STORE.md)
- 年龄分级：**17+**
- 上架地区：美/港/日/韩/新/台/加/澳/英/欧盟等——**不勾中国大陆**
**4.3** 👤 「App 审核信息」→ 加密合规：**Uses Non-Exempt Encryption → No**（标准 TLS + 开源算法，走 Mass Market 豁免）。
**4.4** 👤 定价：**免费**，无 IAP。
**4.5** ⚠️ 👤 「App 审核信息」的**备注（Notes）里必须写清楚 + 附一个审核期可用的测试节点/订阅**（VPN 类不给审核员能连的节点，几乎必被 2.1 拒）。文案模板：
> 本 App 不提供任何节点，用户自带订阅。审核测试节点：`<你放一个稳定的分享链接>`（添加节点→粘贴即可连）。工作原理：xray-core 在系统 Network Extension 里按用户规则转发流量。

---

## 阶段 5 · 截图（你拍我排版）

**5.1** 👤+🤖 按 [APP_STORE.md §4](APP_STORE.md) 场景：iPhone 6.9" 至少 3 张。VPN**连接态**的必须真机（模拟器跑不了扩展）——你把 iPhone 停在目标页面解锁，🤖 我用抓屏工具逐张拍；静态页可用模拟器。
**5.2** 🤖 后期加卖点 caption、套设备框、导出 1290×2796，我全包。

---

## 阶段 6 · GitHub 侧（你点几下，我准备内容）

**6.1** 👤 把 repo 转 **public**（审核要能打开支持 URL / 源码链接）。
**6.2** 👤 Repo → Settings → Pages → Source: Deploy from a branch → **main / `/docs`** → Save。等 1 分钟，拿到 `https://qingzhou-app.github.io/qingzhou/`。
**6.3** 🤖 我已备好 PRIVACY.md（生效日期已填）、宣发博文、官网首页——Pages 一开就能用。

---

## 阶段 7 · TestFlight 内测（1 周）

**7.1** 🤖 我给你精确的 Archive + 上传参数（或你在 Xcode Organizer 点 Distribute App → App Store Connect → Upload）。
**7.2** 👤 ASC → TestFlight：上传的 build 等 5–30 分钟处理完 → 加 **Internal Testers**（你自己，无审核）先自测。
**7.3** 👤 加 **External Testers**（邮件/链接邀请，首次需 Beta App Review 1–2 天）。5–10 人跑 1 周。
**7.4** 双方：同步跑 [ACCEPTANCE.md](ACCEPTANCE.md) 全清单，crash-free。

---

## 阶段 8 · 提交审核

**8.1** 👤 版本页选中 TestFlight 上传的 build。
**8.2** 👤 所有元数据/截图/隐私/合规/审核备注齐全 → **Submit for Review**。
**8.3** 👤 等审核（近年 24–72h，VPN 类可能更久）。被拒看 Resolution Center 的具体条款 → 改 → 重提。VPN 类首次常被 5.4/2.1 卡，材料备好（组织账号已解决 5.4；测试节点解决 2.1）。

---

## macOS 何时上？

建议 **iOS 先上、macOS 晚一版**。原因：macOS 的 content filter 是 **System Extension**，在 Mac App Store
的分发/公证路径要单独查（可能得 Developer ID 直发，或 macOS 版先去掉该功能）。iOS 跑通流程后，
macOS 单独走一遍（隧道 appex 本身可上 MAS，卡点在系统扩展）。喊我时我给 macOS 专门的清单。

---

## 一句话分工

**你做**：网页上点（账号/Identifiers/建 App/填元数据/勾隐私/传包/提审/转 public/开 Pages）+ 准备一个审核测试节点。
**我做**：改工程签名配置、构建 Archive、准备全部文案素材、真机抓截图+排版、部署内容、给你每步的精确命令。

从**阶段 0.4** 开始：你把**组织 Team ID** 发我，我就改签名配置、`xcodegen generate`、试 Archive。
