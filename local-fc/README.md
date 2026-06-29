# local-fc — 手动运行 Firecracker microVM

用途：不依赖完整 E2B 部署，直接手动跑 FC，用于调试 arm64 seccomp、envd 行为等。

## 目录结构

```
local-fc/
  README.md
  vm-config.json       FC 配置文件（base 配置，不跑 E2B init）
  00-setup-tap.sh      建 TAP 网络（每次重启/首次运行）
  01-start-fc.sh       启动 FC（前台，console 输出到终端）
  02-start-fc-bg.sh    启动 FC（后台 + API，用于脚本控制）
  03-snapshot.sh       触发 snapshot create（测 dirty-memory 路径）
  99-cleanup.sh        清理 tap/进程
```

## 快速使用（复现 arm64 seccomp exit 148）

```bash
# 把文件拷到倚天，放在和 rootfs/kernel/firecracker 同目录
# 1. 建网络
sudo bash 00-setup-tap.sh

# 2. 起 VM（不加 --no-seccomp，触发 seccomp 拦截）
sudo bash 01-start-fc.sh

# 2b. 起 VM（加 --no-seccomp，验证无 seccomp 时 VM 正常）
NO_SECCOMP=1 sudo -E bash 01-start-fc.sh

# 3. 抓 seccomp 违规的 syscall 号
sudo dmesg | grep -iE "seccomp|SIGSYS|syscall"
```

## 关于文件路径

脚本默认从当前目录查找以下文件：
- `rootfs.filesystem.build`（rootfs，从 E2B 构建中保留）
- `vmlinux-6.1.158`（guest 内核）
- `firecracker`（FC 二进制，arm64 版）

可通过环境变量覆盖：
```bash
ROOTFS=/path/to/rootfs KERNEL=/path/to/vmlinux FC=/path/to/firecracker bash 01-start-fc.sh
```
