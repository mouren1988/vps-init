#!/usr/bin/env bash
#===================================================================
# Linux 服务器内核网络与系统基线优化脚本 (Debian / Ubuntu 通用)
# 包含: BBR + 25MB缓冲 + 端口池扩容 + 高并发队列 + 1G日志锁定 + IPv4优先
#===================================================================

GREEN="\033[32m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${CYAN}>>> [1/4] 正在优化内核网络参数 (BBR + 25MB缓冲 + 禁慢启动 + 端口池扩容 + 高并发)...${RESET}"
modprobe tcp_bbr 2>/dev/null

# 清理旧同名配置，确保重复执行幂等、干净无残留
sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d;/net.core.rmem_max/d;/net.core.wmem_max/d;/net.ipv4.tcp_rmem/d;/net.ipv4.tcp_wmem/d;/net.ipv4.tcp_fastopen/d;/net.ipv4.tcp_mtu_probing/d;/net.ipv4.tcp_slow_start_after_idle/d;/net.ipv4.tcp_timestamps/d;/net.ipv4.tcp_sack/d;/net.ipv4.tcp_tw_reuse/d;/net.ipv4.tcp_fin_timeout/d;/net.ipv4.tcp_keepalive_time/d;/net.ipv4.ip_local_port_range/d;/net.core.somaxconn/d;/net.ipv4.tcp_max_syn_backlog/d;/net.core.netdev_max_backlog/d;/net.ipv4.ip_forward/d;/vm.swappiness/d' /etc/sysctl.conf

cat >> /etc/sysctl.conf << 'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.tcp_rmem=4096 131072 26214400
net.ipv4.tcp_wmem=4096 65536 26214400
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.ip_local_port_range=10000 65535
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=16384
net.core.netdev_max_backlog=32768
net.ipv4.ip_forward=1
vm.swappiness=10
EOF
sysctl -p >/dev/null 2>&1

echo -e "${CYAN}>>> [2/4] 正在解除单进程与 systemd 后台服务最大连接数限制 (65535)...${RESET}"
grep -q "root soft nofile 65535" /etc/security/limits.conf || echo -e "* soft nofile 65535\n* hard nofile 65535\nroot soft nofile 65535\nroot hard nofile 65535" >> /etc/security/limits.conf
grep -q "^DefaultLimitNOFILE=" /etc/systemd/system.conf && sed -i 's/^DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/' /etc/systemd/system.conf || echo "DefaultLimitNOFILE=65535" >> /etc/systemd/system.conf
systemctl daemon-reload
ulimit -SHn 65535 2>/dev/null

echo -e "${CYAN}>>> [3/4] 正在永久锁定系统日志上限为 1G 并清理超标历史日志...${RESET}"
grep -q "^SystemMaxUse=" /etc/systemd/journald.conf && sed -i 's/^SystemMaxUse=.*/SystemMaxUse=1G/' /etc/systemd/journald.conf || echo "SystemMaxUse=1G" >> /etc/systemd/journald.conf
systemctl restart systemd-journald
journalctl --vacuum-size=1G >/dev/null 2>&1

echo -e "${CYAN}>>> [4/4] 正在校准北京时间并开启 IPv4 优先...${RESET}"
timedatectl set-timezone Asia/Shanghai
grep -q "^precedence ::ffff:0:0/96" /etc/gai.conf 2>/dev/null || echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf

echo -e "\n${GREEN}================== 内核与系统优化完成 ==================${RESET}"
sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control net.core.rmem_max net.ipv4.tcp_rmem net.ipv4.tcp_fastopen net.ipv4.tcp_mtu_probing net.ipv4.tcp_slow_start_after_idle net.ipv4.tcp_keepalive_time net.ipv4.ip_local_port_range net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.ip_forward vm.swappiness
echo -e "连接限制: limits.conf 与 systemd 均已设为 $(grep '^DefaultLimitNOFILE=' /etc/systemd/system.conf | cut -d= -f2)"
echo -e "日志上限: $(grep '^SystemMaxUse=' /etc/systemd/journald.conf) | 当前占用: $(journalctl --disk-usage | awk '{print $7}')"
echo -e "IPv4优先: $(grep '^precedence ::ffff:0:0/96' /etc/gai.conf)"
echo -e "系统时间: $(date)"
echo -e "${GREEN}========================================================${RESET}"
