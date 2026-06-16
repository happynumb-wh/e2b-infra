#!/bin/sh
set -eu

BUSYBOX="{{ .BusyBox }}"
RESULT_PATH="{{ .ResultPath }}"

echo "Starting provisioning script"

{{ if eq .Provider "gcp" }}
# GCP Specific logic
{{ end }}


echo "Switching apt sources to mirrors.ustc.edu.cn"
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources
fi
if [ -f /etc/apt/sources.list ]; then
    sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list
fi

echo "Making configuration immutable"
$BUSYBOX chattr +i /etc/resolv.conf

# Helper function to check if a package is installed
is_package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Install required packages if not already installed
PACKAGES="systemd systemd-sysv openssh-server sudo chrony socat curl ca-certificates fuse3 iptables git nfs-common less nftables iputils-ping jq"
echo "Checking presence of the following packages: $PACKAGES"

MISSING=""
for pkg in $PACKAGES; do
    if ! is_package_installed "$pkg"; then
        echo "Package $pkg is missing, will install it."
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Missing packages detected, installing:$MISSING"
    apt-get -q update
    DEBIAN_FRONTEND=noninteractive DEBCONF_NOWARNINGS=yes apt-get -qq -o=Dpkg::Use-Pty=0 install -y --no-install-recommends $MISSING
else
    echo "All required packages are already installed."
fi

# Set /dev/fuse permissions to 666 for non-root access
# Use systemd-tmpfiles to set permissions at boot
mkdir -p /etc/tmpfiles.d
echo 'z /dev/fuse 0666 root root -' > /etc/tmpfiles.d/fuse.conf

echo "Setting up shell"
echo "export SHELL='/bin/bash'" >/etc/profile.d/shell.sh
echo "export PS1='\w \$ '" >/etc/profile.d/prompt.sh
echo "export PS1='\w \$ '" >>"/etc/profile"
echo "export PS1='\w \$ '" >>"/root/.bashrc"

echo "Use .bashrc and .profile"
echo "if [ -f ~/.bashrc ]; then source ~/.bashrc; fi; if [ -f ~/.profile ]; then source ~/.profile; fi" >>/etc/profile

echo "Remove root password"
passwd -d root

echo "Setting up chrony"
mkdir -p /etc/chrony
cat <<EOF >/etc/chrony/chrony.conf
refclock PHC /dev/ptp0 poll 2 dpoll 2
EOF

# Add a proxy config, as some environments expects it there (e.g. timemaster in Node Dockerimage)
echo "include /etc/chrony/chrony.conf" >/etc/chrony.conf

echo "Setting up SSH"
mkdir -p /etc/ssh
cat <<EOF >>/etc/ssh/sshd_config
PermitRootLogin yes
PermitEmptyPasswords yes
PasswordAuthentication yes
EOF

echo "Increasing inotify watch limit"
echo 'fs.inotify.max_user_watches=65536' | tee -a /etc/sysctl.conf

# Disable kcompactd background page migration. With 2 MiB host-side hugepage
# backing of guest RAM, every migration dirties a destination hugepage from
# the host UFFD's perspective and lands in the next memfile diff, with no
# corresponding workload benefit between snapshots. We trigger compaction
# explicitly pre-pause instead.
echo "Disabling proactive memory compaction"
echo 'vm.compaction_proactiveness=0' | tee -a /etc/sysctl.conf

echo "Don't wait for ttyS0 (serial console kernel logs)"
# This is required when the Firecracker kernel args has specified console=ttyS0
systemctl mask serial-getty@ttyS0.service

echo "Disable network online wait"
systemctl mask systemd-networkd-wait-online.service

echo "Disable system first boot wizard"
# This was problem with Ubuntu 24.04, that differently calculate wizard should be called
# and Linux boot was stuck in wizard until envd wait timeout
systemctl mask systemd-firstboot.service

# Clean machine-id from Docker
rm -rf /etc/machine-id

echo "Linking systemd to init"
ln -sf /lib/systemd/systemd /usr/sbin/init

# ==================== E2B DEBUG (临时排查 networkd/rpcbind hang) ====================
echo "[E2B-DEBUG] Installing diagnostics: forward journal to console + verbose networkd"

# 1) 把 journald 的全部日志转发到 console(=ttyS0 → fc-console 文件),含 debug 级别
#    这样 networkd 失败原因、rpcbind 卡在等什么,都会直接打到 console。
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF >/etc/systemd/journald.conf.d/zz-e2b-debug.conf
[Journal]
ForwardToConsole=yes
MaxLevelConsole=debug
EOF

# 2) systemd-networkd 开 debug 日志(看它每次失败的具体原因)
mkdir -p /etc/systemd/system/systemd-networkd.service.d
cat <<EOF >/etc/systemd/system/systemd-networkd.service.d/zz-e2b-debug.conf
[Service]
Environment=SYSTEMD_LOG_LEVEL=debug
StandardOutput=journal+console
StandardError=journal+console
EOF

# 3) rpcbind 把自身输出也打到 console(看它卡在哪个系统调用/等待)
mkdir -p /etc/systemd/system/rpcbind.service.d
cat <<EOF >/etc/systemd/system/rpcbind.service.d/zz-e2b-debug.conf
[Service]
StandardOutput=journal+console
StandardError=journal+console
EOF

# 4) 一个尽早运行、且不被 rpcbind 阻塞的诊断服务:开机就把网络状态打到 console
cat <<EOF >/etc/systemd/system/e2b-netdebug.service
[Unit]
Description=E2B network state dump (debug)
DefaultDependencies=no
After=systemd-journald.service
Before=sysinit.target
[Service]
Type=oneshot
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
ExecStart=/bin/sh -c 'echo "===E2B-DEBUG ip addr==="; ip addr; echo "===E2B-DEBUG ip route==="; ip route; echo "===E2B-DEBUG resolv.conf==="; cat /etc/resolv.conf; echo "===E2B-DEBUG entropy_avail==="; cat /proc/sys/kernel/random/entropy_avail'
[Install]
WantedBy=sysinit.target
EOF
ln -sf /etc/systemd/system/e2b-netdebug.service /etc/systemd/system/sysinit.target.wants/e2b-netdebug.service
echo "[E2B-DEBUG] Diagnostics installed"
# ==================== E2B DEBUG END ====================

echo "Unlocking immutable configuration"
$BUSYBOX chattr -i /etc/resolv.conf

echo "Finished provisioning script"

# Delete itself
rm -rf /etc/init.d/rcS
rm -rf /usr/local/bin/provision.sh

# Report successful provisioning
printf "0" > "$RESULT_PATH"
