#!/bin/bash

# ================= 1. 转发规则配置 (请在此修改) =================
# 获取本机出网IP (供下面 Single_Rule 使用)
ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')

Single_Rule=(
    # "$ip 1001  192.168.1.1  4443"
    # "$ip 1002  192.168.1.1  4443"
    # "$ip 1003  192.168.1.1  4443"
    # "$ip 1004  192.168.1.1  4443"
    # "$ip 1005  192.168.1.1  4443"
    # "$ip 1006  192.168.1.1  4443"
    # "$ip 1007  192.168.1.1  4443"
    # "$ip 1008  192.168.1.1  4443"
    # "$ip 1009  192.168.1.1  4443"
    # "$ip 1010  192.168.1.1  4443"
    # "$ip 1011  192.168.1.1  4443"
    # "$ip 1012  192.168.1.1  4443"
    # "$ip 1013  192.168.1.1  4443"
    # "$ip 1014  192.168.1.1  4443"
    # "$ip 1015  192.168.1.1  4443"
    # "$ip 1016  192.168.1.1  4443"
    # "$ip 1017  192.168.1.1  4443"
    # "$ip 1018  192.168.1.1  4443"
    # "$ip 1019  192.168.1.1  4443"
    # "$ip 1020  192.168.1.1  4443"
    # "$ip 1021  192.168.1.1  4443"
    # "$ip 1022  192.168.1.1  4443"
    # "$ip 1023  192.168.1.1  4443"
    # "$ip 1024  192.168.1.1  4443"
    # "$ip 1025  192.168.1.1  4443"
    # "$ip 1026  192.168.1.1  4443"
    # "$ip 1027  192.168.1.1  4443"
    # "$ip 1028  192.168.1.1  4443"
    # "$ip 1029  192.168.1.1  4443"
    # "$ip 1030  192.168.1.1  4443"
    # "$ip 1031  192.168.1.1  4443"
    # "$ip 1032  192.168.1.1  4443"
    # "$ip 1033  192.168.1.1  4443"
    # "$ip 1034  192.168.1.1  4443"
    # "$ip 1035  192.168.1.1  4443"
    # "$ip 1036  192.168.1.1  4443"
    # "$ip 1037  192.168.1.1  4443"
    # "$ip 1038  192.168.1.1  4443"
    # "$ip 1039  192.168.1.1  4443"
    # "$ip 1040  192.168.1.1  4443"
    # "$ip 1041  192.168.1.1  4443"
    # "$ip 1042  192.168.1.1  4443"
    # "$ip 1043  192.168.1.1  4443"
    # "$ip 1044  192.168.1.1  4443"
    # "$ip 1045  192.168.1.1  4443"
    # "$ip 1046  192.168.1.1  4443"
    # "$ip 1047  192.168.1.1  4443"
    # "$ip 1048  192.168.1.1  4443"
    # "$ip 1049  192.168.1.1  4443"
    # "$ip 1050  192.168.1.1  4443"
    # "$ip 1051  192.168.1.1  4443"
    # "$ip 1052  192.168.1.1  4443"
    # "$ip 1053  192.168.1.1  4443"
    # "$ip 1054  192.168.1.1  4443"
    # "$ip 1055  192.168.1.1  4443"
    # "$ip 1056  192.168.1.1  4443"
    # "$ip 1057  192.168.1.1  4443"
    # "$ip 1058  192.168.1.1  4443"
    # "$ip 1059  192.168.1.1  4443"
    # "$ip 1060  192.168.1.1  4443"
    # "$ip 1061  192.168.1.1  4443"
    # "$ip 1062  192.168.1.1  4443"
    # "$ip 1063  192.168.1.1  4443"
    # "$ip 1064  192.168.1.1  4443"
    # "$ip 1065  192.168.1.1  4443"
    # "$ip 1066  192.168.1.1  4443"
    # "$ip 1067  192.168.1.1  4443"
    # "$ip 1068  192.168.1.1  4443"
    # "$ip 1069  192.168.1.1  4443"
    # "$ip 1070  192.168.1.1  4443"
    # "$ip 1071  192.168.1.1  4443"
    # "$ip 1072  192.168.1.1  4443"
    # "$ip 1073  192.168.1.1  4443"
    # "$ip 1074  192.168.1.1  4443"
    # "$ip 1075  192.168.1.1  4443"
    # "$ip 1076  192.168.1.1  4443"
    # "$ip 1077  192.168.1.1  4443"
    # "$ip 1078  192.168.1.1  4443"
    # "$ip 1079  192.168.1.1  4443"
    # "$ip 1080  192.168.1.1  4443"
    # "$ip 1081  192.168.1.1  4443"
    # "$ip 1082  192.168.1.1  4443"
    # "$ip 1083  192.168.1.1  4443"
    # "$ip 1084  192.168.1.1  4443"
    # "$ip 1085  192.168.1.1  4443"
    # "$ip 1086  192.168.1.1  4443"
    # "$ip 1087  192.168.1.1  4443"
    # "$ip 1088  192.168.1.1  4443"
    # "$ip 1089  192.168.1.1  4443"
    # "$ip 1090  192.168.1.1  4443"
    # "$ip 1091  192.168.1.1  4443"
    # "$ip 1092  192.168.1.1  4443"
    # "$ip 1093  192.168.1.1  4443"
    # "$ip 1094  192.168.1.1  4443"
    # "$ip 1095  192.168.1.1  4443"
    # "$ip 1096  192.168.1.1  4443"
    # "$ip 1097  192.168.1.1  4443"
    # "$ip 1098  192.168.1.1  4443"
    # "$ip 1099  192.168.1.1  4443"
    # "$ip 1100  192.168.1.1  4443"
)

# ================= 2. 进程互斥锁 =================
exec 9>/dev/shm/forward_single.lock
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
if ! command -v iptables &> /dev/null; then echo -e "${RED}未安装 iptables！${NC}"; exit 1; fi
if ! command -v host &> /dev/null; then echo -e "${RED}未安装 host (bind-utils)！${NC}"; exit 1; fi

# 允许内核转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# ================= 3. 状态持久化与定时任务 =================
BaseName=$(basename "$BASH_SOURCE")
SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
WorkDir="/root/.forward_cache"
mkdir -p "$WorkDir"
WorkFile="$WorkDir/$BaseName"

# 日志文件路径（位于脚本同级目录）
CRON_LOG="${SCRIPT_DIR}/forward_cron.log"
DDNS_LOG="${SCRIPT_DIR}/ddns_change.log"

if ! grep -q "^[[:space:]]*\* \* \* \* \*.*$BaseName" /etc/crontab; then
    sed -i "/$BaseName/d;/开机时立即运行一次转发脚本/d;/每分钟持续检测并维护转发规则/d;/\[节点转发\]/d" /etc/crontab
    cat << EOF >> /etc/crontab

# [节点转发] 开机自动恢复
@reboot   root  bash $SCRIPT_PATH >/dev/null 2>&1
* * * * * root  bash $SCRIPT_PATH >/dev/null 2>&1
EOF
    echo -e "${GREEN}定时任务已同步至 /etc/crontab${NC}"
fi

# ================= 4. 业务功能 (clean/解析/执行) =================
# 清理功能
if [ "$1" = "clean" ]; then
    if [ "$2" ]; then
        [ -f "$WorkFile.rule.$2" ] && { sed "s|-A|-D|" $WorkFile.rule.$2 | bash; rm -f $WorkFile.rule.$2; echo -e "${RED}端口 $2 规则已清除${NC}"; }
    else
        ls $WorkFile.rule.* &>/dev/null && { sed "s|-A|-D|" $WorkFile.rule.* | bash; rm -f $WorkFile.rule.*; echo -e "${RED}全部规则已清除${NC}"; }
    fi
    exit
fi

# 日志文件大小检查（采用 stat 元数据检查，零磁盘读取开销；超过 200MB 自动截取保留最新 100MB）
for log_f in "$CRON_LOG" "$DDNS_LOG"; do
    if [ -f "$log_f" ] && [ "$(stat -c%s "$log_f" 2>/dev/null || echo 0)" -gt 209715200 ]; then
        tail -c 104857600 "$log_f" | tail -n +2 > "${log_f}.tmp" && mv -f "${log_f}.tmp" "$log_f"
    fi
done
NOW_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# 域名解析转换
rm -rf $WorkFile.hosts $WorkFile.domain
for list in "${Single_Rule[@]}"; do list=($list); echo ${list[2]} >> $WorkFile.domain; done
if [ -f "$WorkFile.domain" ]; then
    Domain=$(sort $WorkFile.domain | uniq | grep -v -E '([0-9]{1,3}[\.]){3}[0-9]{1,3}')
    for d in $Domain; do
        d_ip=$(host -4 -t A -W 2 $d | grep "has address" | awk '{print $NF}' | head -1)
        [ "$d_ip" ] && echo "$d $d_ip" >> $WorkFile.hosts
    done
fi

# 导出快照比对
echo "$(iptables -t nat -nL | grep NAT)" > $WorkFile.iptables

# 构造混合排序列表
ALL_PORTS=$( { 
    for r in "${Single_Rule[@]}"; do r=($r); echo "${r[1]}"; done; 
    ls $WorkFile.rule.* 2>/dev/null | awk -F '.' '{print $NF}' | grep -E '^[0-9]+$'; 
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
            sed "s|-A|-D|" $WorkFile.rule.$p | sed "s|iptables|iptables -w|g" | bash >/dev/null 2>&1
            rm -f $WorkFile.rule.$p
            echo -e "${RED}端口 $p 规则失效，已清除${NC}"
            echo "[$NOW_TIME] 端口 $p 规则失效，已清除" >> "$CRON_LOG"
        fi
    else
        rule=($MATCH_RULE)
        Local_IP=${rule[0]}; Local_Port=${rule[1]}; Raw_Target=${rule[2]}; Remote_Port=${rule[3]}
        Remote_IP="$Raw_Target"
        IS_DOMAIN=0
        
        if [[ ! "$Remote_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IS_DOMAIN=1
            Remote_IP=$(grep -w $Remote_IP $WorkFile.hosts | awk '{print $2}')
        fi

        if [ "$Remote_IP" ]; then
            # 检查当前缓存文件里记录的旧 IP 是多少
            OLD_CACHED_IP=""
            if [ -f "$WorkFile.rule.$Local_Port" ]; then
                OLD_CACHED_IP=$(grep -oP '(?<=--to-destination )[0-9.]+' "$WorkFile.rule.$Local_Port" | head -1)
            fi

            ExistingRuleDNAT=$(grep DNAT $WorkFile.iptables | grep -w "dpt:$Local_Port" | grep -w "to:$Remote_IP:$Remote_Port")
            ExistingRuleSNAT=$(grep SNAT $WorkFile.iptables | grep -w "$Remote_IP" | grep -w "dpt:$Remote_Port")
            
            # 【核心优化】：不仅要求 iptables 规则存在，还要求解析出的 Remote_IP 必须和旧缓存 IP 完全一致！
            if [ "$ExistingRuleDNAT" ] && [ "$ExistingRuleSNAT" ] && [ "$OLD_CACHED_IP" == "$Remote_IP" ]; then
                echo -e "${WHITE}端口 $Local_Port 规则一致，已跳过${NC}"
                
                # 针对旧版升级的兜底补齐缓存
                if [ ! -f "$WorkFile.rule.$Local_Port" ]; then
                    echo "
# TARGET: $Raw_Target
# PORT: $Remote_Port
iptables -w -t nat -A PREROUTING -p tcp --dport $Local_Port -j DNAT --to-destination $Remote_IP:$Remote_Port
iptables -w -t nat -A POSTROUTING -d $Remote_IP -p tcp --dport $Remote_Port -j SNAT --to-source $Local_IP
iptables -w -t nat -A PREROUTING -p udp --dport $Local_Port -j DNAT --to-destination $Remote_IP:$Remote_Port
iptables -w -t nat -A POSTROUTING -d $Remote_IP -p udp --dport $Remote_Port -j SNAT --to-source $Local_IP
" > $WorkFile.rule.$Local_Port
                fi
            else
                # 真正发生 IP 漂移、或者首次加载、或者切换域名时，才走到这里更新！
                OLD_RAW_TARGET=""
                OLD_REMOTE_PORT=""
                OLD_IP=""
                if [ -f "$WorkFile.rule.$Local_Port" ]; then
                    OLD_RAW_TARGET=$(grep -oP '(?<=# TARGET: ).*' "$WorkFile.rule.$Local_Port" 2>/dev/null || echo "")
                    OLD_REMOTE_PORT=$(grep -oP '(?<=# PORT: ).*' "$WorkFile.rule.$Local_Port" 2>/dev/null || echo "")
                    [ -z "$OLD_REMOTE_PORT" ] && OLD_REMOTE_PORT=$(grep -oP '(?<=--to-destination [0-9.]+:)[0-9]+' "$WorkFile.rule.$Local_Port" | head -1)
                    OLD_IP=$OLD_CACHED_IP
                    sed "s|-A|-D|" "$WorkFile.rule.$Local_Port" | bash >/dev/null 2>&1
                fi
                
                echo "
# TARGET: $Raw_Target
# PORT: $Remote_Port
iptables -w -t nat -A PREROUTING -p tcp --dport $Local_Port -j DNAT --to-destination $Remote_IP:$Remote_Port
iptables -w -t nat -A POSTROUTING -d $Remote_IP -p tcp --dport $Remote_Port -j SNAT --to-source $Local_IP
iptables -w -t nat -A PREROUTING -p udp --dport $Local_Port -j DNAT --to-destination $Remote_IP:$Remote_Port
iptables -w -t nat -A POSTROUTING -d $Remote_IP -p udp --dport $Remote_Port -j SNAT --to-source $Local_IP
" > "$WorkFile.rule.$Local_Port"
                
                if bash $WorkFile.rule.$Local_Port >/dev/null 2>&1; then
                    echo -e "${GREEN}端口 $Local_Port 规则变化，已更新${NC}"
                    
                    OLD_DESC="无"
                    [ -n "$OLD_RAW_TARGET" ] && OLD_DESC="${OLD_RAW_TARGET}:${OLD_REMOTE_PORT}"
                    
                    echo "[$NOW_TIME] 端口 $Local_Port 规则变化 (${OLD_DESC} -> ${Raw_Target}:${Remote_Port})，已更新" >> "$CRON_LOG"
                    
                    # 仅当真正发生 IP 漂移时才写入 ddns 日志
                    if [ "$IS_DOMAIN" -eq 1 ] && [ -n "$OLD_RAW_TARGET" ] && [ "$OLD_RAW_TARGET" == "$Raw_Target" ] && [ -n "$OLD_IP" ] && [ "$OLD_IP" != "$Remote_IP" ]; then
                        echo "[$NOW_TIME] [DDNS变动] 端口: $Local_Port | 域名: $Raw_Target | IP变化: $OLD_IP -> $Remote_IP:$Remote_Port" >> "$DDNS_LOG"
                    fi
                else
                    echo -e "${RED}端口 $Local_Port 更新失败${NC}"
                    echo "[$NOW_TIME] 端口 $Local_Port 更新失败 (目标: $Raw_Target -> $Remote_IP:$Remote_Port)" >> "$CRON_LOG"
                fi
            fi
        else
            echo -e "${RED}端口 $Local_Port 域名解析失败，已跳过${NC}"
            echo "[$NOW_TIME] 端口 $Local_Port 域名 ($Raw_Target) 解析失败，已跳过" >> "$CRON_LOG"
        fi
    fi
done

rm -f $WorkFile.iptables $WorkFile.hosts $WorkFile.domain
