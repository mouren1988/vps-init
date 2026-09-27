#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SERVERS=(
    "中转1|CN2韩国|root@1.1.1.1:9527"
	"中转2|ALI韩国|root@1.1.1.1:9527"
    "中转3|AWS韩国|root@1.1.1.1:9527"
)

# ==============================================================================
# 【重装系统后 SSH 免密部署排错备忘录】
# 1. 角色说明：
#    - /root/.ssh/authorized_keys : 【锁芯/公钥】重装系统时云厂商自动写入，供本地电脑连入本机。
#    - /root/.ssh/id_ed25519      : 【钥匙/私钥】本机主动去连其他中转机时必须掏出的钥匙！
#
# 2. 重装系统后必做 3 步：
#    ① 确保所有中转机的 SSH 端口已改回 9527，且已安装依赖：apt update && apt install -y iptables dnsutils
#    ② 将登录私钥 id_ed25519 上传至运行本脚本的主控机 /root/.ssh/ 目录下。
#    ③ 私钥权限必须为 600（若拖拽上传变成“执行文件”会导致 SCP 彻底失败）：
#      chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_ed25519 /root/.ssh/authorized_keys
# ==============================================================================

# [按需防呆自检] 检查私钥是否存在，且仅在权限异常时才执行修复
KEY_FILE="/root/.ssh/id_ed25519"
if [ ! -f "$KEY_FILE" ]; then
    echo -e "\033[0;31m❌ [致命错误] 未找到私钥文件: $KEY_FILE\033[0m"
    echo -e "\033[0;33m💡 请先将登录私钥上传至 /root/.ssh/ 目录后再运行本脚本。\033[0m"
    exit 1
elif [ "$(stat -c %a "$KEY_FILE" 2>/dev/null)" != "600" ]; then
    echo -e "\033[0;33m🔧 检测到私钥权限异常，正在自动修正为 600...\033[0m"
    chmod 700 /root/.ssh
    chmod 600 "$KEY_FILE" /root/.ssh/authorized_keys 2>/dev/null
fi

LOCAL_SCRIPT="forward_single.sh"
REMOTE_DIR="/root"
LOG_DIR="./logs"
MAX_RETRIES=3
SSH_OPTS="-o ConnectTimeout=5 -o ServerAliveInterval=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

cd "$(dirname "$0")" || exit 1
if [ ! -f "$LOCAL_SCRIPT" ]; then echo -e "${RED}❌ 找不到 ${LOCAL_SCRIPT}${NC}"; exit 1; fi
mkdir -p "$LOG_DIR"

echo -e "\n${BOLD}==================================================${NC}"
echo -e "${CYAN}🚀 开始并发部署转发规则 | 时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BOLD}==================================================${NC}\n"

deploy_node() {
    local node_id="$1"
    local alias_name="$2"
    local conn_info="$3"
    
    local user_ip=$(echo "$conn_info" | cut -d':' -f1)
    local port=$(echo "$conn_info" | cut -d':' -f2)
    local log_file="${LOG_DIR}/${node_id}.log"
    local remote_tmp="${REMOTE_DIR}/${LOCAL_SCRIPT}.$$.tmp"
    
    echo ">>> [部署开始] 节点: $alias_name ($conn_info)" > "$log_file"

    if [[ "$user_ip" =~ (127\.0\.0\.1|localhost|::1)$ ]]; then
        local local_success=false
        for ((i=1; i<=MAX_RETRIES; i++)); do
            if bash "$LOCAL_SCRIPT" >> "$log_file" 2>&1; then
                local_success=true; break
            fi
            if [ $i -lt $MAX_RETRIES ]; then sleep 2; fi
        done
        if [ "$local_success" = true ]; then
            echo -e "  ${GREEN}✅ [$alias_name] 本地规则热更新成功！${NC}"
            return 0
        else
            echo -e "  ${RED}❌ [$alias_name] 本地执行出错，详见日志: $log_file${NC}"
            return 1
        fi
    fi

    local scp_success=false
    for ((i=1; i<=MAX_RETRIES; i++)); do
        scp -P "$port" $SSH_OPTS "$LOCAL_SCRIPT" "${user_ip}:${remote_tmp}" >> "$log_file" 2>&1
        if [ $? -eq 0 ]; then
            scp_success=true; break
        fi
        if [ $i -lt $MAX_RETRIES ]; then sleep 2; fi
    done

    if [ "$scp_success" = false ]; then
        echo -e "  ${RED}❌ [$alias_name] SCP 传输彻底失败！${NC}"; return 1
    fi

    local ssh_success=false
    for ((i=1; i<=MAX_RETRIES; i++)); do
        # 【排雷修复】：使用 { }; 闭环，确保退出码准确且 100% 清理 tmp 垃圾文件
        timeout 120 ssh -n -p "$port" $SSH_OPTS "$user_ip" \
            "mv -f ${remote_tmp} ${REMOTE_DIR}/${LOCAL_SCRIPT} && { bash ${REMOTE_DIR}/${LOCAL_SCRIPT}; RET=\$?; rm -f ${remote_tmp}; exit \$RET; }" >> "$log_file" 2>&1
            
        if [ $? -eq 0 ]; then
            ssh_success=true; break
        fi
        if [ $i -lt $MAX_RETRIES ]; then sleep 2; fi
    done
    
    if [ "$ssh_success" = true ]; then
        echo -e "  ${GREEN}✅ [$alias_name] 远程规则热更新成功！${NC}"; return 0
    else
        echo -e "  ${RED}❌ [$alias_name] 远程执行出错或锁定，详见日志: $log_file${NC}"; return 1
    fi
}

pids=(); declare -A pid_names
for server_info in "${SERVERS[@]}"; do
    node_id=$(echo "$server_info" | cut -d'|' -f1)
    alias_name=$(echo "$server_info" | cut -d'|' -f2)
    conn_info=$(echo "$server_info" | cut -d'|' -f3)
    deploy_node "$node_id" "$alias_name" "$conn_info" &
    current_pid=$!
    pids+=($current_pid); pid_names[$current_pid]=$alias_name
done

success_count=0; failed_count=0; failed_nodes=()
for pid in "${pids[@]}"; do
    wait "$pid"
    if [ $? -eq 0 ]; then ((success_count++)); else ((failed_count++)); failed_nodes+=("${pid_names[$pid]}"); fi
done

echo -e "\n${BOLD}==================================================${NC}"
echo -e "📊 ${CYAN}部署状态统计报告${NC} | 成功: ${GREEN}${success_count}${NC} | 失败: ${RED}${failed_count}${NC}"
if [ ${#failed_nodes[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️ 失败节点：${NC}"
    for fn in "${failed_nodes[@]}"; do echo -e " - ${RED}${fn}${NC}"; done
fi
echo -e "${BOLD}==================================================${NC}\n"
