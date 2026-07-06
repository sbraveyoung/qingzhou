package xray

// 轻舟本地 patch（非 libXray 上游代码）：运行中原地替换 outbound handler。
//
// 用途：VPN 换节点时不再整条隧道 stop→start（断流 3–10 秒、状态栏图标闪烁），
// 而是在运行中的 xray 实例上把指定 tag 的 outbound handler 热替换成新节点 ——
// 路由 / DNS / inbound / TUN 全不动，新连接立刻走新出口，旧连接随旧 handler 关闭。
//
// 做法与 xray-core 自带的 gRPC HandlerService（AddOutbound/RemoveOutbound，
// app/proxyman/command/command.go）完全同源，只是免掉 api inbound + gRPC 栈
//（NE 扩展 50MB 内存预算容不下）。依赖的都是 xray:api:stable 接口。
//
// 由 scripts/build-libxray.sh 在 gomobile bind 前复制到 $LIBXRAY_DIR/xray/。

import (
	"context"
	"encoding/json"
	"fmt"
	"runtime/debug"

	"github.com/xtls/xray-core/common"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/outbound"
	"github.com/xtls/xray-core/infra/conf"
)

// SwitchOutbound 在运行中的实例上用 outboundJSON（xray 配置 outbounds 数组的
// 单个元素，必须带 tag）替换同 tag 的 handler。失败时尽力把旧 handler 放回并
// 返回错误 —— 调用方（主 App）收到错误会回退到全量重启，不会悬空。
func SwitchOutbound(outboundJSON string) error {
	server := coreServer
	if server == nil || !server.IsRunning() {
		return fmt.Errorf("xray is not running")
	}
	var detour conf.OutboundDetourConfig
	if err := json.Unmarshal([]byte(outboundJSON), &detour); err != nil {
		return fmt.Errorf("parse outbound json: %w", err)
	}
	if detour.Tag == "" {
		return fmt.Errorf("outbound json missing tag")
	}
	cfg, err := detour.Build()
	if err != nil {
		return fmt.Errorf("build outbound config: %w", err)
	}
	mgr, ok := server.GetFeature(outbound.ManagerType()).(outbound.Manager)
	if !ok {
		return fmt.Errorf("outbound manager unavailable")
	}
	ctx := context.Background()
	// 顺序是硬性的：AddHandler 对重复 tag 直接报错，必须先摘旧的。
	// RemoveHandler 只摘引用、不 Close（与上游 HandlerService 相同），旧 handler
	// 保持可用 —— AddHandler 失败还能原样放回。它同时会清掉 defaultHandler
	//（proxy 是第一个 outbound = default），AddHandler 里 defaultHandler == nil
	// 时用新 handler 补位，全局模式的兜底路由不受影响。
	old := mgr.GetHandler(detour.Tag)
	if old != nil {
		if err := mgr.RemoveHandler(ctx, detour.Tag); err != nil {
			return fmt.Errorf("remove old handler: %w", err)
		}
	}
	if err := core.AddOutboundHandler(server, cfg); err != nil {
		if old != nil {
			_ = mgr.AddHandler(ctx, old) // 回滚，别让 proxy 出口凭空消失
		}
		return fmt.Errorf("add new handler: %w", err)
	}
	if old != nil {
		// 新 handler 就位后再关旧的：在途旧连接终止（与全量重启同语义）、资源释放。
		_ = common.Close(old)
	}
	debug.FreeOSMemory()
	return nil
}
