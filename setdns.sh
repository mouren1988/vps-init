#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

# 统一解锁函数（修改配置或安装软件包前必须先解锁）
unlock_files() {
    chattr -i /etc/resolv.conf 2>/dev/null
    chattr -i /etc/systemd/resolved.conf 2>/dev/null
}

# 统一加锁询问函数（默认 Y，支持回车直接锁定双文件）
lock_dns_prompt() {
    read -p "是否锁定配置文件防止被系统重置？[Y/n] (默认: Y): " lock_choice
    lock_choice=${lock_choice:-Y}
    if [[ "$lock_choice" =~ ^[Yy]$ ]]; then
        chattr +i /etc/resolv.conf 2>/dev/null
        if [ -f /etc/systemd/resolved.conf ]; then
            chattr +i /etc/systemd/resolved.conf 2>/dev/null
        fi
        echo "✅ 已锁定 /etc/resolv.conf 与 /etc/systemd/resolved.conf (+i)"
    else
        echo "ℹ️ 未锁定配置文件"
    fi
}

# 部署明文 DNS 函数
apply_plain_dns() {
    local dns1="$1"
    local dns2="$2"
    local desc="$3"

    echo "正在配置 ${desc}..."
    unlock_files

    # 如果之前开启了 systemd-resolved，先停用避免抢占
    if systemctl is-active --quiet systemd-resolved; then
        systemctl disable --now systemd-resolved >/dev/null 2>&1
    fi

    # 删除可能存在的软链接或旧文件，重建为普通实体文件
    rm -f /etc/resolv.conf
    cat << EOF > /etc/resolv.conf
nameserver ${dns1}
nameserver ${dns2}
EOF

    echo "✅ ${desc} 配置完成！"
    lock_dns_prompt
}

# 部署 DoT 加密 DNS 函数
apply_dot_dns() {
    local main_dns="$1"
    local fallback_dns="$2"
    local desc="$3"

    echo "正在配置 ${desc}..."
    
    # 1. 必须在安装软件前解锁，防止 dpkg 替换文件时报错
    unlock_files

    # 2. 检查并安装 systemd-resolved (兼容 Debian 11/12/13)
    if ! command -v resolvectl >/dev/null 2>&1 && [ ! -f /lib/systemd/systemd-resolved ]; then
        echo "检测到系统未安装 systemd-resolved，正在自动安装..."
        apt-get update -y && apt-get install -y systemd-resolved
    fi

    # 3. 写入加密配置 (加入 Domains=~. 防止网卡 DHCP 默认 DNS 抢占)
    cat << EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=${main_dns}
FallbackDNS=${fallback_dns}
Domains=~.
DNSOverTLS=yes
DNSSEC=no
EOF

    # 4. 启动并重启加密解析守护进程
    systemctl enable --now systemd-resolved >/dev/null 2>&1
    systemctl restart systemd-resolved

    # 5. 删除软链接，直接写入实体文件指向 127.0.0.53（以便支持 chattr +i 锁定）
    rm -f /etc/resolv.conf
    cat << 'EOF' > /etc/resolv.conf
nameserver 127.0.0.53
options edns0 trust-ad
EOF

    echo "✅ ${desc} 配置完成！(已接管至本地加密守护进程 127.0.0.53)"
    lock_dns_prompt
}

# ================= 一级主菜单 =================
clear
echo "=========================================="
echo "          DNS 优化与修改工具"
echo "=========================================="
echo "当前 /etc/resolv.conf 状态："
grep -v '^#' /etc/resolv.conf 2>/dev/null | grep -v '^$'
if systemctl is-active --quiet systemd-resolved; then
    echo "------------------------------------------"
    echo "[加密守护进程状态]: 运行中 (DoT 已启用)"
    resolvectl status 2>/dev/null | grep -E "Current DNS Server:|DNS Servers:|DNSOverTLS" | sed 's/^[ \t]*//'
fi
echo "=========================================="
echo "1. 国外 DNS 优化 (Cloudflare & Google) [默认]"
echo "2. 国内 DNS 优化 (阿里 & 腾讯)"
echo "------------------------------------------"
echo "0. 退出脚本"
echo "=========================================="
read -p "请输入你的选择 [0-2] (默认: 1): " region_choice
region_choice=${region_choice:-1}

if [ "$region_choice" = "0" ]; then
    echo "退出脚本。"
    exit 0
elif [ "$region_choice" != "1" ] && [ "$region_choice" != "2" ]; then
    echo "❌ 无效的选择！"
    exit 1
fi

# ================= 二级模式菜单 =================
echo "------------------------------------------"
echo "请选择 DNS 解析模式："
echo "1. 加密 DNS [DoT 853端口 - 防劫持/防污染] [默认]"
echo "2. 明文 DNS [传统 53端口 - 直接解析]"
echo "------------------------------------------"
read -p "请输入模式选择 [1-2] (默认: 1): " mode_choice
mode_choice=${mode_choice:-1}

# ================= 执行逻辑 =================
case "${region_choice}-${mode_choice}" in
    1-1)
        apply_dot_dns \
            "1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 8.8.8.8#dns.google" \
            "9.9.9.9#dns.quad9.net" \
            "国外加密 DNS (CF & Google DoT)"
        ;;
    1-2)
        apply_plain_dns "1.1.1.1" "8.8.8.8" "国外明文 DNS (1.1.1.1 & 8.8.8.8)"
        ;;
    2-1)
        apply_dot_dns \
            "223.5.5.5#dns.alidns.com 223.6.6.6#dns.alidns.com 1.12.12.12#dot.pub" \
            "120.53.53.53#dot.pub" \
            "国内加密 DNS (阿里 & 腾讯 DoT)"
        ;;
    2-2)
        apply_plain_dns "223.5.5.5" "119.29.29.29" "国内明文 DNS (223.5.5.5 & 119.29.29.29)"
        ;;
    *)
        echo "❌ 无效的模式选择！"
        exit 1
        ;;
esac
