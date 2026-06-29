#!/usr/bin/env bash
# 后台启动 FC，通过 Unix socket API 控制
# 用途：脚本化操作、触发 snapshot/dirty 路径测试
set -euo pipefail

ROOTFS="${ROOTFS:-./rootfs.filesystem.build}"
KERNEL="${KERNEL:-./vmlinux-6.1.158}"
FC="${FC:-./firecracker}"
SOCK="${SOCK:-/tmp/fc-local.sock}"
LOG="${LOG:-/tmp/fc-local.log}"

[[ -f "$ROOTFS" ]] || { echo "找不到 rootfs: $ROOTFS"; exit 1; }
[[ -f "$KERNEL" ]] || { echo "找不到 kernel: $KERNEL"; exit 1; }
[[ -f "$FC"     ]] || { echo "找不到 FC 二进制: $FC"; exit 1; }

rm -f "$SOCK"

EXTRA_ARGS=""
[[ "${NO_SECCOMP:-0}" == "1" ]] && EXTRA_ARGS="--no-seccomp"

# 后台启动 FC
"$FC" --api-sock "$SOCK" $EXTRA_ARGS > "$LOG" 2>&1 &
FC_PID=$!
echo "FC PID: $FC_PID  Socket: $SOCK  Log: $LOG"

# 等 socket 就绪
for i in $(seq 1 20); do
    [[ -S "$SOCK" ]] && break
    sleep 0.1
done
[[ -S "$SOCK" ]] || { echo "FC socket 未就绪，查看 $LOG"; exit 1; }

api() { curl -sf -X "${1:-GET}" --unix-socket "$SOCK" "http://localhost/${2}" \
    ${3:+-H 'Content-Type: application/json' -d "$3"}; }

echo "=== 配置 boot-source ==="
api PUT boot-source "{
  \"kernel_image_path\": \"$KERNEL\",
  \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off i8042.noaux i8042.nokbd clocksource=kvm-clock random.trust_cpu=on ip=169.254.0.21::169.254.0.22:255.255.255.252:instance:eth0:off:tap0 init=/sbin/init\"
}"

echo "=== 配置 rootfs ==="
api PUT drives/rootfs "{
  \"drive_id\": \"rootfs\",
  \"path_on_host\": \"$ROOTFS\",
  \"is_root_device\": true,
  \"is_read_only\": false,
  \"io_engine\": \"Sync\"
}"

echo "=== 配置 machine-config ==="
api PUT machine-config '{"vcpu_count":2,"mem_size_mib":512,"smt":false}'

echo "=== 配置网络 ==="
api PUT network-interfaces/eth0 '{"iface_id":"eth0","host_dev_name":"tap0"}'

echo "=== 启动 VM ==="
api PUT actions '{"action_type":"InstanceStart"}'

echo ""
echo "VM 已启动，FC_PID=$FC_PID"
echo "查看 guest console: tail -f $LOG"
echo "调用 API: curl -sf --unix-socket $SOCK http://localhost/<path>"
echo "停止: kill $FC_PID"
echo ""
echo "FC_PID=$FC_PID" > /tmp/fc-local.pid
echo "SOCK=$SOCK" >> /tmp/fc-local.pid
