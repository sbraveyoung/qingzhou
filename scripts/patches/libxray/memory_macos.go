//go:build darwin && !ios

// macOS 隧道扩展的 Go 内存压制 —— 轻舟本地 patch（非 libXray 上游代码）。
//
// 背景：libXray 上游只给 iOS（//go:build ios）做了内存压制（GOMEMLIMIT=30MiB +
// GOGC=10 + 每秒 FreeOSMemory），因为 iOS NE 扩展有 50MB jetsam 硬上限。
// macOS 走的是 memory_other.go 的 no-op —— Go runtime 按默认 GOGC=100 让堆
// 翻倍式增长、且从不主动把空闲页还给 OS，实测扩展 RSS 无约束爬到 1.6GB。
//
// 本文件由 scripts/build-libxray.sh 在 gomobile bind 前复制进
// $LIBXRAY_DIR/memory/，配套把 memory_other.go 的 build tag 收窄为
// !ios && !darwin（见同目录 memory_other.go）。build tag 互斥，对 iOS 构建零影响。
//
// 参数取值（macOS 比 iOS 宽松，理由）：
//   - SetMemoryLimit(192MiB)：macOS 扩展要承载完整版 geoip.dat（22.7MB）的
//     内存 matcher + geosite matcher，30MiB 会 GC 打摆；192MiB 是「用户可接受
//     的常驻」和「留足 matcher + 连接高峰余量」的折中。这是 soft limit，
//     超限只会让 GC 更勤，不会 OOM kill。
//   - SetGCPercent(30)：默认 100 意味着堆养到 live set 的 2 倍才回收；
//     30 让堆贴着 live set 走，CPU 代价对 VPN 转发可忽略。
//   - FreeOSMemory 每 10s：Go 默认 scavenger 归还页面非常慢（分钟级），
//     周期性强制归还让 RSS 跟着 GC 后的真实堆走。iOS 是 1s（贴着 jetsam 线
//     求生），macOS 没有硬上限，10s 足够、CPU 也更省。
package memory

import (
	"runtime/debug"
	"sync"
	"time"
)

const (
	freeInterval = 10 * time.Second
	// 192 MiB —— Go runtime soft memory limit（堆 + runtime 自身结构）
	maxMemory = 192 * 1024 * 1024
)

var initOnce sync.Once

// InitForceFree 由 libXray 的 RunXray / RunXrayFromJSON 在每次启动 xray 时调用。
// 用 sync.Once 保证热切换（reconfigure 反复 Run）不会叠加 forceFree goroutine。
func InitForceFree() {
	initOnce.Do(func() {
		debug.SetGCPercent(30)
		debug.SetMemoryLimit(maxMemory)
		go func() {
			for {
				time.Sleep(freeInterval)
				debug.FreeOSMemory()
			}
		}()
	})
}
