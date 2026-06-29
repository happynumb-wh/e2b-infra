#!/usr/bin/env bash
# 触发 snapshot create → dirty-memory 路径
# 用途：复现 arm64 seccomp exit 148（snapshot/dirty 路径触发）
set -euo pipefail

SOCK="${SOCK:-/tmp/fc-local.sock}"
SNAP_DIR="${SNAP_DIR:-/tmp/fc-snap}"

[[ -S "$SOCK" ]] || { echo "FC 未运行，先跑 02-start-fc-bg.sh"; exit 1; }

api() { curl -sf -X "${1:-GET}" --unix-socket "$SOCK" "http://localhost/${2}" \
    ${3:+-H 'Content-Type: application/json' -d "$3"}; }

mkdir -p "$SNAP_DIR"
SNAPFILE="$SNAP_DIR/snap-$(date +%s)"
MEMFILE="$SNAP_DIR/mem-$(date +%s)"

echo "=== 暂停 VM ==="
api PATCH vm '{"state":"Paused"}'

echo "=== 创建 snapshot（触发 dirty-memory 路径）==="
echo "  snapfile: $SNAPFILE"
echo "  memfile:  $MEMFILE"
api PUT snapshot/create "{
  \"snapshot_path\": \"$SNAPFILE\",
  \"mem_file_path\": \"$MEMFILE\",
  \"snapshot_type\": \"Full\"
}"

echo ""
echo "✓ Snapshot 完成"
echo ""
echo "如果 FC 进程已退出（exit 148）：seccomp 拦截了某个 syscall"
echo "抓 syscall 号："
echo "  sudo dmesg | grep -iE 'seccomp|SIGSYS|syscall='"
echo "  sudo ausearch -ts recent -m SECCOMP 2>/dev/null"
