#!/bin/bash

# ================= 1. IPv6 转发规则配置 (请在此修改) =================
# 获取本机出网IPv6 (供下面 Single_Rule 使用)
ip6=$(ip -6 route get 2001:4860:4860::8888 2>/dev/null | grep -oP 'src \K\S+')

Single_Rule=(
    # "$ip6 1001  2400:3200::1  4443"
    # "$ip6 1002  2400:3200::1  4443"
    # "$ip6 1003  2400:3200::1  4443"
    # "$ip6 1004  2400:3200::1  4443"
    # "$ip6 1005  2400:3200::1  4443"
)

# ================= 2. 进程互斥锁 =================
exec 9>/dev/shm/forward_single_v6.lock
flock -w 15 9 || {
    echo -e "\033[0;33m[警告] 已有实例运行且超过15秒未释放，本次跳过。\033[0m"
    exit 1
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
NC='\033[0m'

# 环境检查
if ! command -v ip6tables &> /dev/null; then echo -e "${RED}未安装 ip6tables！${NC}"; exit 1; fi
if ! command -v host &> /dev/null; then echo -e "${RED}未安装 host (bind9-host/dnsutils)！${NC}"; exit 1; fi

# 允许内核 IPv6 转发
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
echo 1 > /proc/sys/net/ipv6/conf/default/forwarding

# ================= 3. 状态持久化与定时任务 =================
BaseName=$(basename "$BASH_SOURCE")
WorkDir="/root/.forward_cache"
mkdir -p "$WorkDir"
WorkFile="$WorkDir/$BaseName"

SCRIPT_PATH=$(realpath "$0")
if ! grep -q "$BaseName" /etc/crontab; then
    cat << EOF >> /etc/crontab

# [IPv6节点转发] 开机自动恢复
@reboot   root  bash $SCRIPT_PATH
# * * * * * root  flock -xn /dev/shm/${BaseName}.lock -c 'bash $SCRIPT_PATH'
EOF
    echo -e "${GREEN}定时任务已同步至 /etc/crontab${NC}"
fi

# ================= 4. 业务功能 (clean/解析/执行) =================
# 清理功能
if [ "${1:-}" = "clean" ]; then
    if [ "${2:-}" ]; then
        [ -f "$WorkFile.rule.$2" ] && { sed "s|-A|-D|" "$WorkFile.rule.$2" | bash; rm -f "$WorkFile.rule.$2"; echo -e "${RED}端口 $2 规则已清除${NC}"; }
    else
        ls "$WorkFile".rule.* &>/dev/null && { sed "s|-A|-D|" "$WorkFile".rule.* | bash; rm -f "$WorkFile".rule.*; echo -e "${RED}全部规则已清除${NC}"; }
    fi
    exit
fi

# 域名解析转换 (不含冒号 : 的视为域名，解析 AAAA 记录)
rm -rf "$WorkFile.hosts" "$WorkFile.domain"
for list in "${Single_Rule[@]}"; do list=($list); echo "${list[2]}" >> "$WorkFile.domain"; done
if [ -f "$WorkFile.domain" ]; then
    Domain=$(sort "$WorkFile.domain" | uniq | grep -v ':')
    for d in $Domain; do
        d_ip=$(host -6 -t AAAA -W 1 "$d" 2>/dev/null | awk '/has IPv6 address/{print $NF; exit}')
        [ "$d_ip" ] && echo "$d $d_ip" >> "$WorkFile.hosts"
    done
fi

# 导出快照比对
echo "$(ip6tables -t nat -nL | grep NAT)" > "$WorkFile.ip6tables"

# 构造混合排序列表
ALL_PORTS=$( {
    for r in "${Single_Rule[@]}"; do r=($r); echo "${r[1]}"; done;
    ls "$WorkFile".rule.* 2>/dev/null | awk -F '.' '{print $NF}' | grep -E '^[0-9]+$';
} | sort -uV )

for p in $ALL_PORTS; do
    MATCH_RULE=""
    for r in "${Single_Rule[@]}"; do
        temp_r=($r)
        if [ "${temp_r[1]}" == "$p" ]; then
            MATCH_RULE="$r"
            break
        fi
    done

    if [ -z "$MATCH_RULE" ]; then
        if [ -f "$WorkFile.rule.$p" ]; then
            sed "s|-A|-D|" "$WorkFile.rule.$p" | bash >/dev/null 2>&1
            rm -f "$WorkFile.rule.$p"
            echo -e "${RED}端口 $p 规则失效，已清除${NC}"
        fi
    else
        rule=($MATCH_RULE)
        Local_IP=${rule[0]}; Local_Port=${rule[1]}; Remote_IP=${rule[2]}; Remote_Port=${rule[3]}

        if [[ ! "$Remote_IP" =~ : ]]; then
            Remote_IP=$(grep -w "^$Remote_IP" "$WorkFile.hosts" 2>/dev/null | awk '{print $2}')
        fi

        # 将 IPv6 地址标准化为内核一致的小写压缩格式，确保快照比对 100% 匹配
        if [ "$Remote_IP" ]; then
            Remote_IP=$(getent ahostsv6 "$Remote_IP" 2>/dev/null | awk '{print $1; exit}')
        fi
        if [ "$Local_IP" ]; then
            Local_IP=$(getent ahostsv6 "$Local_IP" 2>/dev/null | awk '{print $1; exit}')
        fi

        if [ "$Remote_IP" ] && [ "$Local_IP" ]; then
            ExistingRuleDNAT=$(grep DNAT "$WorkFile.ip6tables" | grep -w "dpt:$Local_Port" | grep -F "to:[$Remote_IP]:$Remote_Port")
            ExistingRuleSNAT=$(grep SNAT "$WorkFile.ip6tables" | grep -F "$Remote_IP" | grep -w "dpt:$Remote_Port")

            if [ "$ExistingRuleDNAT" ] && [ "$ExistingRuleSNAT" ]; then
                echo -e "${WHITE}端口 $Local_Port 规则一致，已跳过${NC}"

                if [ ! -f "$WorkFile.rule.$Local_Port" ]; then
                    echo "
ip6tables -w -t nat -A PREROUTING -p tcp --dport $Local_Port -j DNAT --to-destination [$Remote_IP]:$Remote_Port
ip6tables -w -t nat -A POSTROUTING -d $Remote_IP -p tcp --dport $Remote_Port -j SNAT --to-source $Local_IP
ip6tables -w -t nat -A PREROUTING -p udp --dport $Local_Port -j DNAT --to-destination [$Remote_IP]:$Remote_Port
ip6tables -w -t nat -A POSTROUTING -d $Remote_IP -p udp --dport $Remote_Port -j SNAT --to-source $Local_IP
" > "$WorkFile.rule.$Local_Port"
                fi
            else
                # 变动更新
                [ -f "$WorkFile.rule.$Local_Port" ] && { sed "s|-A|-D|" "$WorkFile.rule.$Local_Port" | bash >/dev/null 2>&1; }
                echo "
ip6tables -w -t nat -A PREROUTING -p tcp --dport $Local_Port -j DNAT --to-destination [$Remote_IP]:$Remote_Port
ip6tables -w -t nat -A POSTROUTING -d $Remote_IP -p tcp --dport $Remote_Port -j SNAT --to-source $Local_IP
ip6tables -w -t nat -A PREROUTING -p udp --dport $Local_Port -j DNAT --to-destination [$Remote_IP]:$Remote_Port
ip6tables -w -t nat -A POSTROUTING -d $Remote_IP -p udp --dport $Remote_Port -j SNAT --to-source $Local_IP
" > "$WorkFile.rule.$Local_Port"

                if bash "$WorkFile.rule.$Local_Port" >/dev/null 2>&1; then
                    echo -e "${GREEN}端口 $Local_Port 规则变化，已更新${NC}"
                else
                    echo -e "${RED}端口 $Local_Port 更新失败${NC}"
                fi
            fi
        else
            echo -e "${RED}端口 $Local_Port 域名解析或本机IPv6获取失败，已跳过${NC}"
        fi
    fi
done

rm -f "$WorkFile.ip6tables" "$WorkFile.hosts" "$WorkFile.domain"
