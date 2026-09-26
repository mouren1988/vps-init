#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

# 严格的 IP 格式校验函数
validate_ip() {
    local ip="$1"
    local stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# 统一解锁函数
unlock_files() {
    chattr -i /etc/resolv.conf 2>/dev/null
    chattr -i /etc/systemd/resolved.conf 2>/dev/null
}

# 状态显示函数（精简直观，自动识别加密/普通模式及真实 DNS 地址）
show_dns_status() {
    echo "------------------------------------------"
    if systemctl is-active --quiet systemd-resolved && grep -q "127.0.0.53" /etc/resolv.conf 2>/dev/null; then
        local dot_dns
        dot_dns=$(grep -E "^DNS=" /etc/systemd/resolved.conf 2>/dev/null | cut -d'=' -f2 | sed 's/#[^ ]*//g')
        echo "当前模式 : 🔒 加密 DNS (DoT)"
        echo "DNS 地址 : ${dot_dns:-未知}"
    else
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

# 准备普通明文环境（解锁、停用加密服务、清理软链接）
prepare_plain_env() {
    unlock_files
    if systemctl is-active --quiet systemd-resolved; then
        systemctl disable --now systemd-resolved >/dev/null 2>&1
    fi
    if [ -L /etc/resolv.conf ]; then
        rm -f /etc/resolv.conf
    fi
}

# 部署明文 DNS 函数
apply_plain_dns() {
    local dns_ips="$1"
    local desc="$2"

    echo "正在配置 ${desc}..."
    prepare_plain_env

    > /etc/resolv.conf
    for ip in ${dns_ips}; do
        echo "nameserver ${ip}" >> /etc/resolv.conf
    done

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

# ================= 菜单主循环 =================
while true; do
    # 一级主菜单
    clear
    echo "=========================================="
    echo "          DNS 优化与修改工具"
    show_dns_status
    echo "1. 国外 DNS 优化 (Cloudflare & Google) [默认]"
    echo "2. 国内 DNS 优化 (阿里 & 腾讯)"
    echo "3. 自定义 DNS"
    echo "------------------------------------------"
    echo "0. 退出脚本"
    echo "=========================================="
    read -p "请输入你的选择 [0-3] (默认: 1): " region_choice
    region_choice=${region_choice:-1}

    case "$region_choice" in
        0)
            echo "退出脚本。"
            exit 0
            ;;
        1|2)
            # 进入二级菜单
            ;;
        3)
            prepare_plain_env
            echo "------------------------------------------"
            
            # 1. 输入主力 DNS
            while true; do
                read -p "首选 DNS: " primary_ip
                if validate_ip "$primary_ip"; then
                    break
                else
                    echo "❌ IP 格式错误，请重新输入合法的 IPv4 地址！"
                fi
            done

            # 2. 输入备用 DNS
            while true; do
                read -p "备选 DNS: " backup_ip
                if validate_ip "$backup_ip"; then
                    break
                else
                    echo "❌ IP 格式错误，请重新输入合法的 IPv4 地址！"
                fi
            done

            apply_plain_dns "$primary_ip $backup_ip" "自定义明文 DNS ($primary_ip, $backup_ip)"
            break
            ;;
        *)
            echo "❌ 无效的选择，请重新输入！"
            sleep 1
            continue
            ;;
    esac

    # 二级模式菜单
    echo "------------------------------------------"
    echo "请选择 DNS 解析模式："
    echo "1. 普通 DNS [默认]"
    echo "2. 加密 DNS [DoT]"
    echo "3. 返回上级菜单"
    echo "------------------------------------------"
    read -p "请输入模式选择 [1-3] (默认: 1): " mode_choice
    mode_choice=${mode_choice:-1}

    if [ "$mode_choice" = "3" ]; then
        continue
    fi

    # 执行逻辑
    case "${region_choice}-${mode_choice}" in
        1-1)
            apply_plain_dns "1.1.1.1 8.8.8.8" "国外普通 DNS (1.1.1.1 & 8.8.8.8)"
            break
            ;;
        1-2)
            apply_dot_dns \
                "1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 8.8.8.8#dns.google" \
                "9.9.9.9#dns.quad9.net" \
                "国外加密 DNS (CF & Google DoT)"
            break
            ;;
        2-1)
            apply_plain_dns "223.5.5.5 119.29.29.29" "国内普通 DNS (223.5.5.5 & 119.29.29.29)"
            break
            ;;
        2-2)
            apply_dot_dns \
                "223.5.5.5#dns.alidns.com 223.6.6.6#dns.alidns.com 1.12.12.12#dot.pub" \
                "120.53.53.53#dot.pub" \
                "国内加密 DNS (阿里 & 腾讯 DoT)"
            break
            ;;
        *)
            echo "❌ 无效的模式选择，正在返回主菜单..."
            sleep 1
            continue
            ;;
    esac
done
