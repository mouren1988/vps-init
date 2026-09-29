#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

echo "正在检测系统架构..."
ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        PKG_ARCH="x86_64"
        ;;
    aarch64|arm64)
        PKG_ARCH="aarch64"
        ;;
    armv7l|armhf)
        PKG_ARCH="armhf"
        ;;
    i386|i686)
        PKG_ARCH="i386"
        ;;
    *)
        echo "❌ 不支持的系统架构: $ARCH"
        exit 1
        ;;
esac

echo "正在从官方获取最新版 Speedtest 客户端下载地址..."
# 访问官方下载页并利用正则自动提取对应架构的最新 .tgz 链接
DOWNLOAD_URL=$(curl -s https://www.speedtest.net/apps/cli | grep -oE "https://[^\"']+\-linux-${PKG_ARCH}\.tgz" | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ 自动获取下载链接失败，正在回退到备用固定链接..."
    DOWNLOAD_URL="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${PKG_ARCH}.tgz"
fi

echo "下载地址: $DOWNLOAD_URL"
echo "正在下载..."
curl -sL -o speedtest.tgz "$DOWNLOAD_URL"

echo "正在解压文件..."
tar -zxvf speedtest.tgz

echo "正在安装到全局命令目录 (/usr/local/bin)..."
chmod +x speedtest
mv speedtest /usr/local/bin/

echo "清理临时文件..."
rm -f speedtest.tgz speedtest.1 speedtest.md

echo "✅ Speedtest 最新版安装完成！直接输入 speedtest 即可测速。"
