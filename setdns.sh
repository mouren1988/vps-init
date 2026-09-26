#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本 (sudo bash $0)"
    exit 1
fi

while true; do
    clear
    echo "===================================="
    echo "          DNS 优化与修改工具          "
    echo "===================================="
    echo "当前 DNS 地址状态："
    if [ -f /etc/resolv.conf ]; then
        grep "nameserver" /etc/resolv.conf
    else
        echo "无 /etc/resolv.conf 文件"
    fi
    echo "------------------------------------"
    echo "1. 国外 DNS 优化 (Cloudflare & Google)"
    echo "   v4: 1.1.1.1  8.8.8.8"
    echo "2. 国内 DNS 优化 (阿里 & 腾讯)"
    echo "   v4: 223.5.5.5  119.29.29.29"
    echo "3. 手动编辑 DNS 配置"
    echo "------------------------------------"
    echo "0. 退出脚本"
    echo "===================================="
    read -p "请输入你的选择 [0-3]: " choice

    case $choice in
        1)
            echo "正在应用国外 DNS..."
            chattr -i /etc/resolv.conf 2>/dev/null
            cat > /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
            chattr +i /etc/resolv.conf
            echo "国外 DNS 设置成功并已锁死！"
            read -p "按回车键继续..."
            ;;
        2)
            echo "正在应用国内 DNS..."
            chattr -i /etc/resolv.conf 2>/dev/null
            cat > /etc/resolv.conf << 'EOF'
nameserver 223.5.5.5
nameserver 119.29.29.29
EOF
            chattr +i /etc/resolv.conf
            echo "国内 DNS 设置成功并已锁死！"
            read -p "按回车键继续..."
            ;;
        3)
            echo "正在解除锁定并打开编辑器..."
            chattr -i /etc/resolv.conf 2>/dev/null
            vim /etc/resolv.conf
            read -p "是否需要加锁防篡改？(Y/n，默认Y): " lock_choice
            # 如果用户直接回车（即 lock_choice 为空），则将其默认设为 y
            lock_choice=${lock_choice:-y}
            if [ "$lock_choice" = "y" ] || [ "$lock_choice" = "Y" ]; then
                chattr +i /etc/resolv.conf
                echo "已加锁！"
            else
                echo "未加锁。"
            fi
            read -p "按回车键继续..."
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效的选择，请重新输入！"
            sleep 1
            ;;
    esac
done
