package libXray

// 轻舟本地 patch（非 libXray 上游代码）：SwitchOutbound 的 gomobile 导出，
// 请求/响应封装与 xray_wrapper.go 的既有函数完全一致
//（base64(JSON request) → base64(nodep.CallResponse)）。
// 由 scripts/build-libxray.sh 在 gomobile bind 前复制到 $LIBXRAY_DIR/。

import (
	"encoding/base64"
	"encoding/json"

	"github.com/xtls/libxray/nodep"
	"github.com/xtls/libxray/xray"
)

type switchOutboundRequest struct {
	OutboundJSON string `json:"outboundJson,omitempty"`
}

// SwitchOutbound 原地替换运行中 xray 实例的 outbound handler（换节点不重启）。
// base64Text: base64(JSON{outboundJson})，outboundJson 是 xray 配置 outbounds
// 数组的单个元素（含 tag）。
func SwitchOutbound(base64Text string) string {
	var response nodep.CallResponse[string]
	req, err := base64.StdEncoding.DecodeString(base64Text)
	if err != nil {
		return response.EncodeToBase64("", err)
	}
	var request switchOutboundRequest
	if err := json.Unmarshal(req, &request); err != nil {
		return response.EncodeToBase64("", err)
	}
	err = xray.SwitchOutbound(request.OutboundJSON)
	return response.EncodeToBase64("", err)
}
