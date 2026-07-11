# DNS 与防污染 —— 设计与踩坑（改 DNS/fakedns 前必读）

> 轻舟的 DNS 是「fakedns 分层 + 按域名分流 + 公共 DNS 上游强制直连」。改这里前先读本文
> + `docs/IPV6.md`（全链路 IPv4 的取舍）。核心配置在 `XrayConfig/XrayConfigComposer.swift`
> 的 `buildDNS` / `buildRouting`。

## 为什么需要 fakedns（分层查号）

规则模式要按**域名**分流（国内直连 / 国外代理），但连接建立时用的是 IP，路由只看到 IP 就
不知道是哪个域名了。fakedns 的巧计：app 查域名 → fakedns 发一个假 IP（`198.18.0.0/15`）→
app 连假 IP → TUN 靠 sniffing 的 fakedns 反查回真域名 → 于是路由/access log 都拿到域名。

- fakedns **只配 IPv4 池**（不配 `fc00::/18`）：配 IPv6 池会对无真实 AAAA 的域名也发假 IPv6，
  浏览器 IPv6 优先会走死路。`queryStrategy: UseIPv4`，不解析 AAAA。详见 `docs/IPV6.md`。
- **海外域名的 A 查询被 fakedns 接管** → 域名甩给墙外节点解析（节点在干净环境，天然避污染）。
  所以海外域名根本不在本地查真实 DNS。

## 头号坑：DNS 上游查询绕代理（东方甄选案，2026-07-12 真机定位）

**症状**：规则模式下「东方甄选」等国内 app 首屏/直播/下单页必先慢或失败；切「直连」模式立刻全好。

**根因（铁证）**：fakedns 接不住的查询（AAAA、或 app 硬用的公共 DNS）会 **fallthrough 到真实
上游** `8.8.8.8` / `1.1.1.1`。而这些上游查询**本身经过路由**：`8.8.8.8` 非国内 IP、不命中
`geoip:cn` → 落到 catch-all `tcp,udp→proxy` → **被当海外流量踹去代理节点（英国）**。于是：
①DNS 绕地球半圈，几百 ms/超时；②从海外出口查国内域名，拿到「服务海外用户」的边缘 IP →
国内连它被风控/超时。app 每个请求前都要查号，DNS 一卡就全盘卡。

**判别实验**：切直连模式——还慢=非轻舟锅；立刻好=轻舟 DNS 环节。东方甄选=后者。

## 解法：DNS 第 3 档（防污染 + 强制直连，build 16）

以 mihomo/sing-box 的成熟范式为参照（见会话调研 `competitor-gap-report.md`），在 xray-core 上落地：

1. **公共 DNS 上游强制直连**（`buildRouting` rule/global）：路由加
   `{network:udp, port:53, ip:[8.8.8.8,8.8.4.4,1.1.1.1,1.0.0.1,223.5.5.5,223.6.6.6] → direct}`，
   在用户规则之前钉死。DNS 上游查询**绝不绕代理**——这是东方甄选 bug 的正修
   （= 用户手动加 `8.8.8.8/1.1.1.1→直连` 的 workaround 默认化，真机双实证）。
2. **海外/漏网查询走 DoH 加密直连**（`buildDNS` rule）：`https+local://dns.google/dns-query`
   + cloudflare 兜底。`https+local://` = 加密（GFW 看不到查询内容、无法投毒）+ `+local` 绕过
   路由直接 Freedom 直连。**xray v26.6.27 亲测接受此语法**（`DNSAntiPollutionPrecheckTests`
   用 `XrayCore.testConfig` 让 xray 真构建一遍——防「语法不认→隧道起不来」）。
   明文 `8.8.8.8/1.1.1.1` 作 DoH 被干扰时的兜底，由上面的 direct 规则保证也走直连。
3. **国内域名走阿里直连**（不变）：`{223.5.5.5, domains:[geosite:cn]}`。

## 刻意不做：GeoIP 回退校验（expectIPs）—— 会踩 cctv 坑

mihomo 的 `fallback-filter` 用 GeoIP 校验国内 DNS 的答案、非 CN IP 视为污染重查。xray 的对应物
是 `expectIPs: [geoip:cn]`。**但我们不用**：`buildDNS` 注释里记的央视案证明——国内 CDN
（`p.data.cctv.com` 等）的合法边缘 IP 常在**非 CN 注册段**（港澳/国际 CDN/IPv6），`geoip:cn`
校验会把它当污染丢弃 → fallthrough 到海外查 → 拿海外边缘 → 国内连它超时。抄 mihomo 抄到这条
= 踩自己踩过的坑。**海外域名靠 fakedns+节点已经天然防污染，不需要这层校验。**

## xray-core 的 DNS 能力边界（换内核才能补的）

- ✅ 有：DoH（`https://`/`https+local://`）、DoQ（`quic+local://`）、per-server `domains`/
  `queryStrategy`/`skipFallback`、`expectIPs` GeoIP 过滤、DNS 定向出站（DNS tag + `inboundTag`
  路由 + `sendThrough`，维护者在 XTLS/Xray-core#6151 亲证）。
- ❌ 内核级限制：xray 内部 resolver **丢掉发起连接的 inboundTag** → DNS 无法按「哪个连接触发」
  路由（#6151、#4987 都 closed not planned）。轻舟不需要 per-connection DNS，不受影响。

## 验证纪律

- 改 `buildDNS`/`buildRouting` 后跑 `DNSAntiPollutionPrecheckTests`（`XrayCore.testConfig` 真构建，
  datDir 指向 `Apps/Tunnel-Shared/Resources` 的 geoip.dat）——**防「配置语法 xray 不认→真机隧道
  起不来→用户断网」**。DoH/新 DNS server 语法尤其必过此关再上机。
- ⚠️ **JSON 序列化把 `/` 转义成 `\/`**：断言 config 字符串时别用带 `/` 的整串（如
  `https+local://dns.google/dns-query`），用不含 `/` 的片段（`dns.google` + `https+local`）。
- **必须真机三方回归**（此环境测不了真拨号）：①东方甄选类国内 app 恢复 ②央视/CN CDN 不回归
  ③YouTube 等海外站不回归。三者其一坏 = DNS 改动有回归，回退。
