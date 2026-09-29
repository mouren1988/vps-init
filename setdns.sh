#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "❌ 系统缺少 flock (util-linux)，无法保证脚本并发安全！"
    exit 1
fi

if ! command -v ss >/dev/null 2>&1; then
    echo "❌ 系统缺少 ss (iproute2)，无法安全确认 53 端口状态！"
    exit 1
fi

mkdir -p /run/lock
exec 9>/run/lock/setdns.lock
if ! flock -n 9; then
    echo "❌ 检测到另一个 setdns.sh 实例正在运行，请勿并发执行！"
    exit 1
fi

# 如果是通过 bash <(curl ...) 临时运行的，自动将自身安装到 /usr/local/bin/setdns
if [[ "$0" == /dev/fd/* ]] && [ ! -f /usr/local/bin/setdns ]; then
    curl -fsSL https://raw.githubusercontent.com/mouren1988/vps-init/main/setdns.sh -o /usr/local/bin/setdns 2>/dev/null && chmod +x /usr/local/bin/setdns
fi

ORIG_DNS_FILE="/etc/resolv.conf.orig"

TX_ACTIVE=0
IN_ROLLBACK=0
SNAP_DIR=""
SNAP_HAD_RESOLV=0
SNAP_HAD_CONF=0
SNAP_HAD_OVERRIDE=0
SNAP_RESOLV_IMMUTABLE=0
SNAP_CONF_IMMUTABLE=0
SNAP_RESOLVED_ACTIVE=0
SNAP_RESOLVED_ENABLED=0
SNAP_SMARTDNS_ACTIVE=0
SNAP_SMARTDNS_ENABLED=0

ignore_err() {
    if "$@" >/dev/null 2>&1; then
        :
    fi
    return 0
}

is_file_immutable() {
    local target="$1"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        if lsattr -d "$target" 2>/dev/null | awk '{print $1}' | grep -q "i"; then
            return 0
        fi
    fi
    return 1
}

validate_ip() {
    local ip="$1"
    local stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local OIFS=$IFS
        IFS='.'
        read -r -a octets <<< "$ip"
        IFS=$OIFS
        [[ 10#${octets[0]} -le 255 && 10#${octets[1]} -le 255 && 10#${octets[2]} -le 255 && 10#${octets[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

is_usable_orig_ip() {
    local ip="$1"
    if ! validate_ip "$ip"; then
        return 1
    fi
    if [[ "$ip" =~ ^127\. ]]; then
        return 1
    fi
    if [ "$ip" = "0.0.0.0" ]; then
        return 1
    fi
    return 0
}

backup_original_dns() {
    if [ ! -f "$ORIG_DNS_FILE" ]; then
        local raw_ips
        raw_ips=$(awk '/^nameserver/ && $2 !~ /^127\./ && $2 != "::1" {print $2}' /etc/resolv.conf 2>/dev/null)
        if [ -z "$raw_ips" ] && [ -f /run/systemd/resolve/resolv.conf ]; then
            raw_ips=$(awk '/^nameserver/ && $2 !~ /^127\./ && $2 != "::1" {print $2}' /run/systemd/resolve/resolv.conf 2>/dev/null)
        fi
        local valid_list=""
        local ip
        for ip in $raw_ips; do
            if is_usable_orig_ip "$ip"; then
                if [ -z "$valid_list" ]; then
                    valid_list="$ip"
                else
                    valid_list="${valid_list}"$'\n'"${ip}"
                fi
            fi
        done
        if [ -n "$valid_list" ]; then
            echo "$valid_list" > "$ORIG_DNS_FILE"
            ignore_err chmod 600 "$ORIG_DNS_FILE"
        fi
    fi
}

get_fallback_dns() {
    local valid_count=0
    if [ -f "$ORIG_DNS_FILE" ] && [ -s "$ORIG_DNS_FILE" ]; then
        local line
        while IFS= read -r line; do
            if is_usable_orig_ip "$line"; then
                echo "$line"
                valid_count=$((valid_count + 1))
            fi
        done < "$ORIG_DNS_FILE"
    fi
    if [ "$valid_count" -eq 0 ]; then
        echo "8.8.8.8"
    fi
}

unlock_files() {
    ignore_err chattr -i /etc/resolv.conf
    ignore_err chattr -i /etc/smartdns/smartdns.conf
    if is_file_immutable /etc/resolv.conf; then
        echo "❌ 无法解除 /etc/resolv.conf 的 +i 锁定属性！"
        return 1
    fi
    if is_file_immutable /etc/smartdns/smartdns.conf; then
        echo "❌ 无法解除 /etc/smartdns/smartdns.conf 的 +i 锁定属性！"
        return 1
    fi
    return 0
}

atomic_write_resolv() {
    local tmp_file="/etc/resolv.conf.tmp.$$"
    if ! cat > "$tmp_file"; then
        echo "❌ 写入临时文件 $tmp_file 失败！"
        rm -f "$tmp_file"
        return 1
    fi

    if ! unlock_files; then
        rm -f "$tmp_file"
        return 1
    fi

    if [ -L /etc/resolv.conf ]; then
        if ! rm -f /etc/resolv.conf; then
            echo "❌ 无法移除旧的 /etc/resolv.conf 软链接！"
            rm -f "$tmp_file"
            return 1
        fi
    fi

    if ! mv -f "$tmp_file" /etc/resolv.conf; then
        echo "❌ 原子替换 /etc/resolv.conf 失败！"
        rm -f "$tmp_file"
        return 1
    fi

    ignore_err chmod 644 /etc/resolv.conf
    return 0
}

take_system_snapshot() {
    SNAP_DIR="/run/lock/setdns_snap.$$"
    if ! mkdir -p "$SNAP_DIR"; then
        echo "❌ 无法创建事务快照目录 $SNAP_DIR！"
        return 1
    fi

    SNAP_HAD_RESOLV=0
    SNAP_HAD_CONF=0
    SNAP_HAD_OVERRIDE=0
    SNAP_RESOLV_IMMUTABLE=0
    SNAP_CONF_IMMUTABLE=0
    SNAP_RESOLVED_ACTIVE=0
    SNAP_RESOLVED_ENABLED=0
    SNAP_SMARTDNS_ACTIVE=0
    SNAP_SMARTDNS_ENABLED=0

    if is_file_immutable /etc/resolv.conf; then
        SNAP_RESOLV_IMMUTABLE=1
    fi
    if is_file_immutable /etc/smartdns/smartdns.conf; then
        SNAP_CONF_IMMUTABLE=1
    fi

    if [ -L /etc/resolv.conf ]; then
        SNAP_HAD_RESOLV=1
        if ! cp -a /etc/resolv.conf "$SNAP_DIR/resolv.conf"; then
            echo "❌ 备份 /etc/resolv.conf 软链接失败，中止操作！"
            rm -rf "$SNAP_DIR"
            return 1
        fi
    elif [ -e /etc/resolv.conf ]; then
        SNAP_HAD_RESOLV=1
        if ! cp -a /etc/resolv.conf "$SNAP_DIR/resolv.conf"; then
            echo "❌ 备份 /etc/resolv.conf 失败，中止操作！"
            rm -rf "$SNAP_DIR"
            return 1
        fi
    fi

    if [ -f /etc/smartdns/smartdns.conf ]; then
        SNAP_HAD_CONF=1
        if ! cp -a /etc/smartdns/smartdns.conf "$SNAP_DIR/smartdns.conf"; then
            echo "❌ 备份 /etc/smartdns/smartdns.conf 失败，中止操作！"
            rm -rf "$SNAP_DIR"
            return 1
        fi
    fi

    local override_file="/etc/systemd/system/smartdns.service.d/override.conf"
    if [ -f "$override_file" ]; then
        SNAP_HAD_OVERRIDE=1
        if ! cp -a "$override_file" "$SNAP_DIR/override.conf"; then
            echo "❌ 备份 systemd override.conf 失败，中止操作！"
            rm -rf "$SNAP_DIR"
            return 1
        fi
    fi

    if systemctl is-active --quiet systemd-resolved; then
        SNAP_RESOLVED_ACTIVE=1
    fi
    if systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
        SNAP_RESOLVED_ENABLED=1
    fi

    if systemctl is-active --quiet smartdns; then
        SNAP_SMARTDNS_ACTIVE=1
    fi
    if systemctl is-enabled --quiet smartdns 2>/dev/null; then
        SNAP_SMARTDNS_ENABLED=1
    fi

    TX_ACTIVE=1
    return 0
}

restore_system_snapshot() {
    if [ "$IN_ROLLBACK" -eq 1 ]; then
        return 0
    fi
    IN_ROLLBACK=1
    TX_ACTIVE=0

    echo "🔄 正在执行全局事务状态回滚..."
    local rollback_ok=1

    if ! unlock_files; then
        rollback_ok=0
    fi

    if [ -n "$SNAP_DIR" ] && [ -d "$SNAP_DIR" ]; then
        if [ "$SNAP_HAD_RESOLV" -eq 1 ]; then
            rm -f /etc/resolv.conf
            if ! cp -a "$SNAP_DIR/resolv.conf" /etc/resolv.conf 2>/dev/null; then
                echo "❌ 回滚 /etc/resolv.conf 失败！"
                rollback_ok=0
            fi
        else
            rm -f /etc/resolv.conf
        fi

        if [ "$SNAP_HAD_CONF" -eq 1 ]; then
            mkdir -p /etc/smartdns
            if ! cp -a "$SNAP_DIR/smartdns.conf" /etc/smartdns/smartdns.conf 2>/dev/null; then
                echo "❌ 回滚 /etc/smartdns/smartdns.conf 失败！"
                rollback_ok=0
            fi
        else
            rm -f /etc/smartdns/smartdns.conf
        fi

        local override_file="/etc/systemd/system/smartdns.service.d/override.conf"
        if [ "$SNAP_HAD_OVERRIDE" -eq 1 ]; then
            mkdir -p /etc/systemd/system/smartdns.service.d
            if ! cp -a "$SNAP_DIR/override.conf" "$override_file" 2>/dev/null; then
                echo "❌ 回滚 $override_file 失败！"
                rollback_ok=0
            fi
        else
            rm -f "$override_file"
        fi
    else
        rollback_ok=0
    fi

    ignore_err systemctl daemon-reload

    if [ "$SNAP_SMARTDNS_ENABLED" -eq 1 ]; then
        if ! systemctl enable smartdns >/dev/null 2>&1; then
            rollback_ok=0
        fi
    else
        if systemctl is-enabled --quiet smartdns 2>/dev/null; then
            if ! systemctl disable smartdns >/dev/null 2>&1; then
                rollback_ok=0
            fi
        fi
    fi

    if [ "$SNAP_SMARTDNS_ACTIVE" -eq 1 ]; then
        if ! systemctl restart smartdns >/dev/null 2>&1; then
            rollback_ok=0
        fi
    else
        if systemctl is-active --quiet smartdns; then
            if ! systemctl stop smartdns >/dev/null 2>&1; then
                rollback_ok=0
            fi
        fi
    fi

    if [ "$SNAP_RESOLVED_ENABLED" -eq 1 ]; then
        if ! systemctl enable systemd-resolved >/dev/null 2>&1; then
            rollback_ok=0
        fi
    else
        if systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
            if ! systemctl disable systemd-resolved >/dev/null 2>&1; then
                rollback_ok=0
            fi
        fi
    fi

    if [ "$SNAP_RESOLVED_ACTIVE" -eq 1 ]; then
        if ! systemctl start systemd-resolved >/dev/null 2>&1; then
            rollback_ok=0
        fi
    else
        if systemctl is-active --quiet systemd-resolved; then
            if ! systemctl stop systemd-resolved >/dev/null 2>&1; then
                rollback_ok=0
            fi
        fi
    fi

    if [ "$SNAP_RESOLV_IMMUTABLE" -eq 1 ] && [ -e /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
        if ! chattr +i /etc/resolv.conf 2>/dev/null; then
            rollback_ok=0
        fi
    fi
    if [ "$SNAP_CONF_IMMUTABLE" -eq 1 ] && [ -f /etc/smartdns/smartdns.conf ]; then
        if ! chattr +i /etc/smartdns/smartdns.conf 2>/dev/null; then
            rollback_ok=0
        fi
    fi

    if [ -n "$SNAP_DIR" ] && [ -d "$SNAP_DIR" ]; then
        rm -rf "$SNAP_DIR"
    fi

    IN_ROLLBACK=0
    if [ "$rollback_ok" -eq 1 ]; then
        echo "✅ 已完整回滚至操作前状态并通过逐项恢复校验。"
        return 0
    else
        echo "⚠️ 回滚流程已执行，但部分状态恢复异常，请人工检查 DNS 与服务状态！"
        return 1
    fi
}

cleanup_system_snapshot() {
    TX_ACTIVE=0
    if [ -n "$SNAP_DIR" ] && [ -d "$SNAP_DIR" ]; then
        rm -rf "$SNAP_DIR"
    fi
}

on_script_exit() {
    local exit_code=$?
    if [ "$TX_ACTIVE" -eq 1 ]; then
        echo ""
        echo "⚠️ 捕获到脚本中途异常中断或信号退出，正在自动触发事务回滚..."
        restore_system_snapshot
        if [ "$exit_code" -eq 0 ]; then
            exit 1
        fi
    fi
    exit "$exit_code"
}

on_signal_interrupt() {
    exit 130
}

trap on_signal_interrupt INT TERM HUP
trap on_script_exit EXIT

check_lock_status() {
    if is_file_immutable /etc/resolv.conf; then
        echo "🔐 已锁定 (+i 防篡改)"
        return 0
    fi
    echo "🔓 未锁定 (可自由修改)"
    return 0
}

check_port_53_conflict() {
    local ss_out
    if ! ss_out=$(ss -H -lntup '( sport = :53 )' 2>/dev/null); then
        echo "❌ 执行 ss 检测 53 端口状态失败！"
        return 1
    fi
    local line
    local has_conflict=0
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        if [[ "$line" == *'("smartdns",'* ]]; then
            continue
        fi
        if [[ "$line" == *'("systemd-resolve",'* ]]; then
            continue
        fi
        if [ "$has_conflict" -eq 0 ]; then
            echo "❌ 检测到 53 端口正被其它非预期进程或未知服务占用："
            has_conflict=1
        fi
        echo "$line"
    done <<< "$ss_out"

    if [ "$has_conflict" -eq 1 ]; then
        echo "请先停止或卸载上述占用 53 端口的服务后再试！"
        return 1
    fi
    return 0
}

get_os_repo_domain() {
    local test_domain="deb.debian.org"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "${ID:-}" = "ubuntu" ]; then
            test_domain="archive.ubuntu.com"
        elif [[ "${ID_LIKE:-}" == *"ubuntu"* ]]; then
            test_domain="archive.ubuntu.com"
        fi
    fi
    echo "$test_domain"
}

verify_dns_query() {
    local domain="$1"
    local mode="$2"
    if [ -z "$domain" ]; then
        domain=$(get_os_repo_domain)
    fi
    if [ "$mode" = "local" ]; then
        if command -v dig >/dev/null 2>&1; then
            if ! dig @127.0.0.1 "$domain" A +time=3 +tries=1 +short 2>/dev/null | grep -qE '^[0-9]+\.'; then
                return 1
            fi
        fi
        if ! getent ahostsv4 "$domain" >/dev/null 2>&1; then
            return 1
        fi
        return 0
    fi
    if getent ahostsv4 "$domain" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

install_smartdns_with_temp_dns() {
    local test_domain
    test_domain=$(get_os_repo_domain)
    local used_temp_dns=0

    echo "🔍 正在检测软件源域名 (${test_domain}) IPv4 解析状态..."
    if verify_dns_query "$test_domain" "sys"; then
        echo "✅ 当前软件源域名解析正常，可直接安装组件。"
    else
        echo "⚠️ 检测到当前 DNS 无法解析软件源，正在启用临时应急 DNS 通道..."
        if ! {
            echo "options timeout:2 attempts:1"
            for ip in $(get_fallback_dns | head -n 1) 8.8.8.8 1.1.1.1; do
                echo "nameserver ${ip}"
            done
        } | atomic_write_resolv; then
            return 1
        fi
        used_temp_dns=1

        if ! verify_dns_query "$test_domain" "sys"; then
            echo "❌ 临时应急 DNS 仍无法解析 ${test_domain}！"
            return 1
        fi
        echo "✅ 临时应急 DNS 二次验证通过 (${test_domain} 解析成功)！"
    fi

    local apt_opts=(
        -o Acquire::Retries=2
        -o Acquire::ForceIPv4=true
        -o Acquire::http::Timeout=10
        -o Acquire::https::Timeout=10
    )
    export DEBIAN_FRONTEND=noninteractive

    if ! (apt-get "${apt_opts[@]}" update && apt-get "${apt_opts[@]}" install -y smartdns); then
        echo "❌ SmartDNS 软件包下载或安装失败！"
        return 1
    fi

    if [ "$used_temp_dns" -eq 1 ]; then
        if [ "$SNAP_HAD_RESOLV" -eq 1 ] && [ -n "$SNAP_DIR" ] && [ -d "$SNAP_DIR" ]; then
            rm -f /etc/resolv.conf
            if ! cp -a "$SNAP_DIR/resolv.conf" /etc/resolv.conf 2>/dev/null; then
                echo "❌ 恢复安装前的原始 /etc/resolv.conf 失败！"
                return 1
            fi
        fi
    fi

    return 0
}

show_dns_status() {
    local orig_ips="未记录"
    if [ -f "$ORIG_DNS_FILE" ] && [ -s "$ORIG_DNS_FILE" ]; then
        orig_ips=$(get_fallback_dns | paste -sd '  ' -)
    fi
    local lock_stat
    lock_stat=$(check_lock_status)

    echo "------------------------------------------"
    if systemctl is-active --quiet smartdns && grep -qE "^nameserver[[:space:]]+127\.0\.0\.1" /etc/resolv.conf 2>/dev/null; then
        local backup_ips
        backup_ips=$(awk '/^nameserver/ && $2 != "127.0.0.1" {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd '  ' -)
        if grep -q "^server-https" /etc/smartdns/smartdns.conf 2>/dev/null; then
            local doh_dns
            doh_dns=$(awk '/^server-https/ {print $2}' /etc/smartdns/smartdns.conf 2>/dev/null | sed -E 's#https://([^/]+)/.*#\1#' | paste -sd '  ' -)
            echo "当前模式 : 🔒 加密 DNS [DoH + SmartDNS 缓存]"
            echo "主力上游 : ${doh_dns:-未知} (127.0.0.1)"
            echo "故障逃生 : ${backup_ips:-无} (原机默认 DNS)"
        else
            local smart_plain_dns
            smart_plain_dns=$(awk '/^server[[:space:]]+/ {print $2}' /etc/smartdns/smartdns.conf 2>/dev/null | paste -sd '  ' -)
            echo "当前模式 : ⚡ 明文 DNS [SmartDNS 缓存优化]"
            echo "主力上游 : ${smart_plain_dns:-未知} (127.0.0.1)"
            echo "故障逃生 : ${backup_ips:-无} (原机默认 DNS)"
        fi
    else
        local plain_dns
        plain_dns=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd '  ' -)
        echo "当前模式 : 📄 普通明文 DNS [不使用 SmartDNS]"
        echo "当前地址 : ${plain_dns:-未配置}"
        echo "原厂备份 : ${orig_ips}"
    fi
    echo "文件状态 : ${lock_stat}"
    echo "------------------------------------------"
}

lock_dns_prompt() {
    read -p "是否锁定配置文件防止被系统重置？[Y/n] (默认: Y): " lock_choice
    lock_choice=${lock_choice:-Y}
    if [[ "$lock_choice" =~ ^[Yy]$ ]]; then
        local lock_ok=1
        if ! chattr +i /etc/resolv.conf 2>/dev/null; then
            lock_ok=0
        elif ! is_file_immutable /etc/resolv.conf; then
            lock_ok=0
        fi

        if [ -f /etc/smartdns/smartdns.conf ]; then
            if ! chattr +i /etc/smartdns/smartdns.conf 2>/dev/null; then
                lock_ok=0
            elif ! is_file_immutable /etc/smartdns/smartdns.conf; then
                lock_ok=0
            fi
        fi

        if [ "$lock_ok" -eq 1 ]; then
            echo "✅ 已锁定配置文件 (+i)"
        else
            echo "⚠️ 锁定配置文件 (+i) 失败（当前文件系统或虚拟化环境可能不支持 chattr +i）"
        fi
    else
        echo "ℹ️ 未锁定配置文件"
    fi
}

apply_plain_dns() {
    local dns_ips="$1"
    local desc="$2"

    echo "正在配置 ${desc}..."
    if ! take_system_snapshot; then
        exit 1
    fi

    if ! unlock_files; then
        restore_system_snapshot
        exit 1
    fi

    if ! {
        for ip in ${dns_ips}; do
            echo "nameserver ${ip}"
        done
    } | atomic_write_resolv; then
        echo "❌ 写入 /etc/resolv.conf 失败！"
        restore_system_snapshot
        exit 1
    fi

    if ! verify_dns_query "" "sys"; then
        echo "⚠️ 警告：所配置的明文 DNS 无法完成系统级解析抽检！"
        restore_system_snapshot
        exit 1
    fi

    if systemctl is-active --quiet smartdns; then
        if ! systemctl disable --now smartdns >/dev/null 2>&1; then
            echo "❌ 停止 SmartDNS 服务失败！"
            restore_system_snapshot
            exit 1
        fi
    elif systemctl is-enabled --quiet smartdns 2>/dev/null; then
        if ! systemctl disable smartdns >/dev/null 2>&1; then
            echo "❌ 禁用 SmartDNS 自启失败！"
            restore_system_snapshot
            exit 1
        fi
    fi

    if systemctl is-active --quiet systemd-resolved; then
        if ! systemctl disable --now systemd-resolved >/dev/null 2>&1; then
            echo "❌ 停止 systemd-resolved 服务失败！"
            restore_system_snapshot
            exit 1
        fi
    elif systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
        if ! systemctl disable systemd-resolved >/dev/null 2>&1; then
            echo "❌ 禁用 systemd-resolved 自启失败！"
            restore_system_snapshot
            exit 1
        fi
    fi

    cleanup_system_snapshot
    echo "✅ ${desc} 配置完成！"
    lock_dns_prompt
    echo -e "\n📊 配置后最新状态："
    show_dns_status
}

apply_smartdns() {
    local proto="$1"
    local upstreams="$2"
    local desc="$3"

    echo "正在配置 ${desc}..."
    if ! take_system_snapshot; then
        exit 1
    fi

    if ! unlock_files; then
        restore_system_snapshot
        exit 1
    fi

    if ! command -v smartdns >/dev/null 2>&1; then
        echo "检测到系统未安装 SmartDNS，准备自动安装..."
        if ! install_smartdns_with_temp_dns; then
            echo "❌ SmartDNS 安装阶段未完成，正在回滚初始状态..."
            restore_system_snapshot
            exit 1
        fi
    fi

    if ! check_port_53_conflict; then
        restore_system_snapshot
        exit 1
    fi

    if [ "$SNAP_RESOLVED_ACTIVE" -eq 1 ]; then
        ignore_err systemctl disable --now systemd-resolved
    elif [ "$SNAP_RESOLVED_ENABLED" -eq 1 ]; then
        ignore_err systemctl disable systemd-resolved
    fi

    if ! check_port_53_conflict; then
        echo "❌ 停止 systemd-resolved 后 53 端口仍被占用！"
        restore_system_snapshot
        exit 1
    fi

    mkdir -p /etc/smartdns
    local tmp_conf="/etc/smartdns/smartdns.conf.tmp.$$"
    cat << 'EOF' > "$tmp_conf"
mkdir -p /etc/smartdns
    local tmp_conf="/etc/smartdns/smartdns.conf.tmp.$$"
    cat << 'EOF' > "$tmp_conf"
# =================================================================
# SmartDNS 极速缓存优化配置 (1C1G 轻量级防劫持 / 游戏加速秒开参数)
# =================================================================

# [本地监听] 仅监听本机回环 53 端口，不对公网开放，防止外部扫描与 DDoS 反射攻击
bind 127.0.0.1:53

# [最大并发保护] 限制最大并发查询请求数为 2048，防止异常程序疯狂发起 DNS 请求撑爆 1C1G 内存
# max-query-limit 2048

# [内存缓存上限] 最多缓存 16384 条域名记录（常驻内存仅约 10MB~15MB，满额自动按 LRU 淘汰旧记录，绝不内存泄漏）
cache-size 16384

# [禁止缓存落盘] 强制关闭磁盘持久化，保持 100% 纯内存缓存运行，重启服务即彻底清空旧缓存并减少磁盘写入
cache-persist no

# [自动预取保鲜] 常用活跃域名在 TTL 即将到期前，后台自动静默刷新，确保在线玩家永远命中 0.1ms 内存缓存
prefetch-domain yes

# [过期缓存救急] 开启后，当冷门域名刚过期或遇跨国网络瞬断时，先返回缓存旧 IP 救急，同时后台立即异步刷新
serve-expired yes

# [过期保留时限] 闲置过期的缓存最多保留 86400 秒（24小时），超过 24 小时无人访问则从内存中彻底删除释放
serve-expired-ttl 86400

# [救急缓存有效期] 使用过期旧 IP 救急时，告知系统该记录仅在 1 秒内有效；后台几十毫秒内完成刷新后，1 秒后无缝切入最新 IP
serve-expired-reply-ttl 1

# [过期预取窗口] 已过期的缓存在 28800 秒（8小时）内若曾被访问过，后台仍会定期主动刷新 IP，防止隔夜上线拿到失效旧 IP
# serve-expired-prefetch-time 28800

# SmartDNS提供了两种测速模式，分别是ping和tcp。优先测443端口，其次80端口，最后ping
speed-check-mode tcp:443,tcp:80,ping
# [关闭节点测速] 禁用 Ping/TCP 测速，避免首次解析被迫等待测速完成而产生数百毫秒的首包卡顿
# speed-check-mode none

# response-mode三种模式：first-ping(默认) / fastest-ip(最佳IP) / fastest-response(最快响应)
# response-mode first-ping
response-mode fastest-ip
# [最快响应模式] 多个上游 DNS 并发查询时，谁最先返回结果就立即采用谁，实现最低查询延迟与天然主备容灾
# response-mode fastest-response

# [禁用 IPv6 解析] 强制对 IPv6 (AAAA) 查询直接返回 SOA，防止纯 IPv4 机器或单栈代理因等待 IPv6 超时而转圈卡顿
force-AAAA-SOA yes

# [精简日志级别] 仅记录 error 错误级别日志，避免高频 DNS 查询产生大量日志写满小容量 VPS 磁盘并损耗 IO
log-level error

# =================================================================
# 上游 DNS 服务器列表 (由脚本根据所选模式自动生成)
# =================================================================
EOF

    if [ "$proto" = "doh" ]; then
        for url in ${upstreams}; do
            echo "server-https ${url}" >> "$tmp_conf"
        done
    else
        for ip in ${upstreams}; do
            echo "server ${ip}" >> "$tmp_conf"
        done
    fi

    if ! mv -f "$tmp_conf" /etc/smartdns/smartdns.conf; then
        echo "❌ 替换 /etc/smartdns/smartdns.conf 失败！"
        rm -f "$tmp_conf"
        restore_system_snapshot
        exit 1
    fi

    local override_file="/etc/systemd/system/smartdns.service.d/override.conf"
    mkdir -p /etc/systemd/system/smartdns.service.d
    cat << 'EOF' > "$override_file"
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=20

[Service]
Restart=always
RestartSec=1
EOF

    systemctl daemon-reload
    if ! systemctl enable smartdns >/dev/null 2>&1; then
        echo "❌ 设置 SmartDNS 开机自启失败！"
        restore_system_snapshot
        exit 1
    fi

    if ! systemctl restart smartdns; then
        echo "❌ SmartDNS 启动失败！最近错误日志如下："
        journalctl -u smartdns -n 20 --no-pager
        restore_system_snapshot
        exit 1
    fi

    if ! systemctl is-active --quiet smartdns; then
        echo "❌ SmartDNS 未处于运行状态！最近错误日志如下："
        journalctl -u smartdns -n 20 --no-pager
        restore_system_snapshot
        exit 1
    fi

    if ! {
        echo "nameserver 127.0.0.1"
        for fb_ip in $(get_fallback_dns | head -n 2); do
            echo "nameserver ${fb_ip}"
        done
    } | atomic_write_resolv; then
        echo "❌ 写入 /etc/resolv.conf 失败！"
        restore_system_snapshot
        exit 1
    fi

    local verify_domain
    verify_domain=$(get_os_repo_domain)
    if ! verify_dns_query "$verify_domain" "local"; then
        echo "⚠️ 警告：SmartDNS 已启动，但首次真实解析双重抽检 (${verify_domain}) 失败！"
        journalctl -u smartdns -n 20 --no-pager
        restore_system_snapshot
        exit 1
    fi

    cleanup_system_snapshot
    echo "✅ ${desc} 配置完成并通过真实解析检验！"
    lock_dns_prompt
    echo -e "\n📊 配置后最新状态："
    show_dns_status
}

backup_original_dns

while true; do
    clear
    echo "=========================================="
    echo "          DNS 优化与修改工具"
    show_dns_status
    echo "1. 国外 DNS 优化 (Google & Cloudflare) [默认]"
    echo "2. 国内 DNS 优化 (阿里 & 腾讯)"
    echo "3. 自定义 DNS"
    echo "4. 一键恢复机器原厂默认 DNS 地址"
    echo "5. 文件解锁 (解除配置文件 +i 锁定)"
    echo "------------------------------------------"
    echo "0. 退出脚本"
    echo "=========================================="
    read -p "请输入你的选择 [0-5] (默认: 1): " region_choice
    region_choice=${region_choice:-1}

    case "$region_choice" in
        0)
            echo "退出脚本。"
            exit 0
            ;;
        1|2)
            echo "------------------------------------------"
            echo "请选择 DNS 解析模式："
            echo "1. 加密 DNS [DoH + SmartDNS 缓存] (防劫持落地机推荐) [默认]"
            echo "2. 明文 DNS [SmartDNS 缓存优化]"
            echo "3. 明文 DNS [普通模式 / 不使用 SmartDNS] (无 UDP/53 劫持的健康机器推荐)"
            echo "4. 返回上级菜单"
            echo "------------------------------------------"
            read -p "请输入模式选择 [1-4] (默认: 1): " mode_choice
            mode_choice=${mode_choice:-1}

            if [ "$mode_choice" = "4" ]; then
                continue
            fi

            case "${region_choice}-${mode_choice}" in
                1-1)
                    apply_smartdns "doh" \
                        "https://1.1.1.1/dns-query https://8.8.8.8/dns-query https://1.0.0.1/dns-query https://8.8.4.4/dns-query" \
                        "国外加密 DNS (DoH + SmartDNS 缓存)"
                    break
                    ;;
                1-2)
                    apply_smartdns "plain" \
                        "1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4" \
                        "国外明文 DNS (SmartDNS 缓存优化)"
                    break
                    ;;
                1-3)
                    apply_plain_dns "1.1.1.1 8.8.8.8" "国外普通明文 DNS (不使用 SmartDNS)"
                    break
                    ;;
                2-1)
                    apply_smartdns "doh" \
                        "https://223.5.5.5/dns-query https://1.12.12.12/dns-query https://223.6.6.6/dns-query https://120.53.53.53/dns-query" \
                        "国内加密 DNS (DoH + SmartDNS 缓存)"
                    break
                    ;;
                2-2)
                    apply_smartdns "plain" \
                        "223.5.5.5 119.29.29.29 223.6.6.6 182.254.116.116" \
                        "国内明文 DNS (SmartDNS 缓存优化)"
                    break
                    ;;
                2-3)
                    apply_plain_dns "223.5.5.5 119.29.29.29" "国内普通明文 DNS (不使用 SmartDNS)"
                    break
                    ;;
                *)
                    echo "❌ 无效的模式选择，正在返回主菜单..."
                    sleep 1
                    continue
                    ;;
            esac
            ;;
        3)
            echo "------------------------------------------"
            while true; do
                read -p "首选 DNS: " primary_ip
                if validate_ip "$primary_ip"; then
                    break
                else
                    echo "❌ IP 格式错误，请重新输入合法的 IPv4 地址！"
                fi
            done

            while true; do
                read -p "备选 DNS (直接回车可跳过): " backup_ip
                if [ -z "$backup_ip" ]; then
                    break
                elif validate_ip "$backup_ip"; then
                    break
                else
                    echo "❌ IP 格式错误，请重新输入合法的 IPv4 地址！"
                fi
            done

            echo "------------------------------------------"
            echo "请选择自定义 DNS 的运行模式："
            echo "1. 普通模式 [不使用 SmartDNS / 直接写入系统] [默认]"
            echo "2. SmartDNS 模式 [开启本地内存缓存优化]"
            echo "3. 返回主菜单"
            echo "------------------------------------------"
            read -p "请输入模式选择 [1-3] (默认: 1): " custom_mode
            custom_mode=${custom_mode:-1}

            if [ "$custom_mode" = "3" ]; then
                continue
            elif [ "$custom_mode" = "1" ]; then
                apply_plain_dns "$primary_ip $backup_ip" "自定义普通明文 DNS (${primary_ip}${backup_ip:+, $backup_ip})"
                break
            elif [ "$custom_mode" = "2" ]; then
                apply_smartdns "plain" "$primary_ip $backup_ip" "自定义明文 DNS [SmartDNS 缓存优化] (${primary_ip}${backup_ip:+, $backup_ip})"
                break
            else
                echo "❌ 无效的模式选择，正在返回主菜单..."
                sleep 1
                continue
            fi
            ;;
        4)
            if [ -f "$ORIG_DNS_FILE" ] && [ -s "$ORIG_DNS_FILE" ]; then
                orig_list=$(get_fallback_dns | paste -sd ' ' -)
                apply_plain_dns "$orig_list" "恢复机器原厂默认 DNS 地址 ($orig_list)"
                break
            else
                echo "❌ 未找到原厂 DNS 备份记录（可能运行脚本前已是 127.0.0.x），请使用 [3. 自定义 DNS] 手动指定！"
                sleep 2
                continue
            fi
            ;;
        5)
            if unlock_files; then
                echo "✅ 已成功解除 /etc/resolv.conf 与 SmartDNS 配置文件的锁定 (-i)！"
            fi
            echo -e "\n📊 解锁后最新状态："
            show_dns_status
            break
            ;;
        *)
            echo "❌ 无效的选择，请重新输入！"
            sleep 1
            continue
            ;;
    esac
done
