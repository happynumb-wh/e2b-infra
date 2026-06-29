#!/usr/bin/env bash
# 前台启动 FC，console 直接输出到当前终端
# 用途：交互式调试，看 guest 启动日志
set -euo pipefail

ROOTFS="${ROOTFS:-./rootfs.filesystem.build}"
KERNEL="${KERNEL:-./vmlinux-6.1.158}"
FC="${FC:-./firecracker}"
SOCK="/tmp/fc-local-$$.sock"

[[ -f "$ROOTFS" ]] || { echo "找不到 rootfs: $ROOTFS"; exit 1; }
[[ -f "$KERNEL" ]] || { echo "找不到 kernel: $KERNEL"; exit 1; }
[[ -f "$FC"     ]] || { echo "找不到 FC 二进制: $FC"; exit 1; }

EXTRA_ARGS=""
if [[ "${NO_SECCOMP:-0}" == "1" ]]; then
    echo "⚠  --no-seccomp 已启用（用于排除 seccomp 干扰）"
    EXTRA_ARGS="--no-seccomp"
fi

echo "FC:     $FC"
echo "Kernel: $KERNEL"
echo "Rootfs: $ROOTFS"
echo "Socket: $SOCK"
echo ""
echo "按 Ctrl-A + X 退出 FC 控制台"
echo "================================"

# 用 vm-config.json，但替换里面的路径
CONFIG=$(cat "$(dirname "$0")/vm-config.json" \
    | sed "s|./vmlinux-6.1.158|$KERNEL|" \
    | sed "s|./rootfs.filesystem.build|$ROOTFS|")

TMPCONFIG=$(mktemp /tmp/fc-config-XXXX.json)
echo "$CONFIG" > "$TMPCONFIG"
trap "rm -f $TMPCONFIG $SOCK" EXIT

exec "$FC" \
    --api-sock "$SOCK" \
    --config-file "$TMPCONFIG" \
    $EXTRA_ARGS
