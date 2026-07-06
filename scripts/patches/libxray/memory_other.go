//go:build !ios && !darwin

// 轻舟本地 patch：把上游 memory_other.go 的 build tag 从 !ios 收窄为 !ios && !darwin，
// 给 memory_macos.go（darwin && !ios）让位 —— 否则两个文件在 macOS slice 上
// 同时编译，InitForceFree 重复定义。
// 由 scripts/build-libxray.sh 在 gomobile bind 前覆盖到 $LIBXRAY_DIR/memory/。
package memory

func InitForceFree() {}
