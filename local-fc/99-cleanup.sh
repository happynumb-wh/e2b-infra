#!/usr/bin/env bash
# 清理：停 FC 进程、删 TAP、清临时文件
set -uo pipefail

TAP="${TAP_NAME:-tap0}"

# 停 FC
if [[ -f /tmp/fc-local.pid ]]; then
    source /tmp/fc-local.pid 2>/dev/null
    [[ -n "${FC_PID:-}" ]] && kill "$FC_PID" 2>/dev/null && echo "✓ FC($FC_PID) 已停止"
    rm -f /tmp/fc-local.pid
fi
# 也杀所有 firecracker 进程
pkill -f "firecracker.*fc-local" 2>/dev/null || true

# 删 TAP
if ip link show "$TAP" &>/dev/null; then
    ip link del "$TAP" && echo "✓ $TAP 已删除"
fi

# 清 socket / config
rm -f /tmp/fc-local.sock /tmp/fc-config-*.json
echo "✓ 清理完成"
