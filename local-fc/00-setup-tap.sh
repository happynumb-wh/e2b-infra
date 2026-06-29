#!/usr/bin/env bash
# 创建 TAP 设备和 host 侧网络，VM 用 169.254.0.21/30，tap 用 169.254.0.22/30
set -euo pipefail

TAP="${TAP_NAME:-tap0}"

# 已存在则跳过
if ip link show "$TAP" &>/dev/null; then
    echo "$TAP 已存在，跳过创建"
    ip addr show "$TAP"
    exit 0
fi

ip tuntap add "$TAP" mode tap
ip addr add 169.254.0.22/30 dev "$TAP"
ip link set "$TAP" up
echo "✓ $TAP 已创建，host 侧 IP: 169.254.0.22，VM 侧 IP: 169.254.0.21"

# 可选：开启 ip_forward + NAT 让 VM 出外网
# echo 1 > /proc/sys/net/ipv4/ip_forward
# iptables -t nat -A POSTROUTING -s 169.254.0.20/30 -j MASQUERADE
