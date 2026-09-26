#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

# 统一解锁函数
unlock_files() {
    chattr -i /etc/resolv.conf 2>/dev/null
    chattr -i /etc/systemd/resolved.conf 2>/dev/null
}

# 状态显示函数（精简直观，自动识别加密/普通模式及真实 DNS 地址）
show_dns_status() {
    echo "------------------------------------------"
    if systemctl is-active --quiet systemd-resolved && grep -q "127.0.0.53" /etc/resolv.conf 2>/dev/null; then
        # 提取加密配置中的真实上游 DNS IP（去除 # 后的校验域名以保持清爽）
        local dot_dns
        dot_dns=$(grep -E "^DNS=" /etc/systemd/resolved.conf 2>/dev/null | cut -d'=' -f2 | sed 's/#[^ ]*//g')
        echo "当前模式 : 🔒 加密 DNS (DoT)"
        echo "DNS 地址 : ${dot_dns:-未知}"
    else
        # 提取普通明文配置中的 nameserver IP
        local plain_dns
        plain_dns=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd '  ' -)
        echo "当前模式 : 📄 普通 DNS (明文)"
        echo "DNS 地址 : ${plain_dns:-未配置}"
    fi
    echo "------------------------------------------"
}

# 统一加锁询问函数（默认 Y）
lock_dns_prompt() {
    read -p "是否锁定配置文件防止被系统重置？[Y/n] (默认: Y): " lock_choice
    lock_choice=${lock_choice:-Y}
    if [[ "$lock_choice" =~ ^[Yy]$ ]]; then
        chattr +i /etc/resolv.conf 2>/dev/null
        if [ -f /etc/systemd/resolved.conf ]; then
            chattr +i /etc/systemd/resolved.conf 2>/dev/null
        fi
        echo "✅ 已锁定配置文件 (+i)"
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

    if systemctl is-active --quiet systemd-resolved; then
        systemctl disable --now systemd-resolved >/dev/null 2>&1
    fi

    rm -f /etc/resolv.conf
    cat << EOF > /etc/resolv.conf
nameserver ${dns1}
nameserver ${dns2}
EOF

    echo "✅ ${desc} 配置完成！"
    lock_dns_prompt
    echo -e "\n📊 配置后最新状态："
    show_dns_status
}

# 部署 DoT 加密 DNS 函数
apply_dot_dns() {
    local main_dns="$1"
    local fallback_dns="$2"
    local desc="$3"

    echo "正在配置 ${desc}..."
    unlock_files

    # 检查并安装 systemd-resolved (兼容 Debian 11/12/13)
    if ! command -v resolvectl >/dev/null 2>&1 && [ ! -f /lib/systemd/systemd-resolved ]; then
        echo "检测到系统未安装 systemd-resolved，正在自动安装..."
        apt-get update -y && apt-get install -y systemd-resolved
    fi

    cat << EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=${main_dns}
FallbackDNS=${fallback_dns}
Domains=~.
DNSOverTLS=yes
DNSSEC=no
EOF

    systemctl enable --now systemd-resolved >/dev/null 2>&1
    systemctl restart systemd-resolved

    rm -f /etc/resolv.conf
    cat << 'EOF' > /etc/resolv.conf
nameserver 127.0.0.53
options edns0 trust-ad
EOF

    echo "✅ ${desc} 配置完成！"
    lock_dns_prompt
    echo -e "\n📊 配置后最新状态："
    show_dns_status
}

# ================= 一级主菜单 =================
clear
echo "=========================================="
echo "          DNS 优化与修改工具"
show_dns_status
echo "1. 国外 DNS 优化 (默认)"
echo "2. 国内 DNS 优化"
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
echo "1. 加密 DNS DoT (默认)"
echo "2. 普通 DNS"
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
        apply_plain_dns "1.1.1.1" "8.8.8.8" "国外普通 DNS (1.1.1.1 & 8.8.8.8)"
        ;;
    2-1)
        apply_dot_dns \
            "223.5.5.5#dns.alidns.com 223.6.6.6#dns.alidns.com 1.12.12.12#dot.pub" \
            "120.53.53.53#dot.pub" \
            "国内加密 DNS (阿里 & 腾讯 DoT)"
        ;;
    2-2)
        apply_plain_dns "223.5.5.5" "119.29.29.29" "国内普通 DNS (223.5.5.5 & 119.29.29.29)"
        ;;
    *)
        echo "❌ 无效的模式选择！"
        exit 1
        ;;
esac
