#!/bin/bash

# ==============================================================================
# 游戏下载 CDN 自动化管理与测速工具 (菜单交互版)
# ==============================================================================

GAME_DOMAINS=(
  "Purple:gs-purple.download.ncupdate.com"
  "Aion1:aionclive.ncupdate.com"
  "Aion2:a2kr.ncupdate.com"
  "Stove1:eclipsepc-dl.game.onstove.com"
  "Stove2:eclipse-live-down.game.playstove.com"
)

DEFAULT_IPS=(
  "3.166.228.50"
  "54.239.163.107"
  "13.35.36.109"
  "99.86.18.105"
  "13.249.231.29"
  "14.0.43.11"
  "2.17.106.198"
  "47.52.50.183"
)

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# 机房代码转直观中文名称函数
translate_pop() {
  local pop="$1"
  case "$pop" in
    NRT*) echo "日本/东京/amazon.com ($pop)" ;;
    SIN*) echo "新加坡/amazon.com ($pop)" ;;
    ICN*) echo "韩国/首尔/amazon.com ($pop)" ;;
    HKG*) echo "中国/香港/amazon.com ($pop)" ;;
    *)    echo "海外/amazon.com ($pop)" ;;
  esac
}

# 核心测速与展示函数
run_test() {
  local ips=("$@")
  NC_DOM="gs-purple.download.ncupdate.com"
  NC_FILE="http://gs-purple.download.ncupdate.com/Purple/PurpleInstaller_2_25_1029_8.exe"
  AWS_DOM="awscli.amazonaws.com"
  AWS_FILE="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"

  echo -e "${CYAN}==========================================================================================================${RESET}"
  printf "%-16s | %-30s | %-14s | %-24s | %-8s | %-10s\n" "测试 IP" "机房与区域归属" "协议支持" "可用游戏域名" "握手延迟" "实测单线程带宽"
  echo -e "${CYAN}==========================================================================================================${RESET}"

  RAW_RESULTS=()

  for ip in "${ips[@]}"; do
    res_443=$(curl -sI -m 3 --resolve "aionclive.ncupdate.com:443:$ip" "https://aionclive.ncupdate.com/" | tr -d '\r')
    pop=$(echo "$res_443" | grep -i "x-amz-cf-pop:" | awk '{print $2}')
    
    if [ -z "$pop" ]; then
      res_80=$(curl -sI -m 2 --resolve "aionclive.ncupdate.com:80:$ip" "http://aionclive.ncupdate.com/" | tr -d '\r')
      pop=$(echo "$res_80" | grep -i "x-amz-cf-pop:" | awk '{print $2}')
    fi

    if [ -n "$pop" ]; then
      cdn_type="$(translate_pop "$pop")"
      proto="HTTPS+HTTP满血"
      compat="全部AWS游戏域名通用"
      stat=$(curl -s -m 6 --resolve "$AWS_DOM:443:$ip" -o /dev/null -w "%{time_connect} %{speed_download}" "$AWS_FILE")
    else
      cdn_type="第三方/副牌CDN"
      proto="仅HTTP(80)"
      ok_doms=""
      for entry in "${GAME_DOMAINS[@]}"; do
        tag=${entry%:*}
        dom=${entry#*:}
        res=$(curl -si -m 2 --resolve "$dom:80:$ip" "http://$dom/" | tr -d '\r')
        if echo "$res" | grep -qiE "(<Code>AccessDenied</Code>|c5d86b27c8a9d91|x-amz-cf-id)"; then
          ok_doms="${ok_doms}${tag} "
        fi
      done

      if [ -z "$ok_doms" ]; then
        printf "%-16s | %-30s | %-14s | ${RED}%-24s${RESET} | %-8s | %-10s\n" "$ip" "未知或超时死节点" "不通/未绑定" "❌ 全不可用" "---" "0.00 MB/s"
        continue
      else
        compat="$ok_doms"
      fi
      stat=$(curl -s -m 6 --resolve "$NC_DOM:80:$ip" -o /dev/null -w "%{time_connect} %{speed_download}" "$NC_FILE")
    fi

    ms=$(echo "$stat" | awk '{printf "%.0f", $1*1000}')
    mb=$(echo "$stat" | awk '{printf "%.2f", $2/1048576}')

    is_fast=$(awk "BEGIN {print ($mb >= 15.0) ? 1 : 0}")
    is_slow=$(awk "BEGIN {print ($mb < 2.0) ? 1 : 0}")

    if [ "$is_fast" -eq 1 ]; then
      color="$GREEN"
      [ -n "$pop" ] && RAW_RESULTS+=("$ip|$cdn_type|$mb|$ms")
    elif [ "$is_slow" -eq 1 ]; then
      color="$RED"
    else
      color="$YELLOW"
    fi

    printf "%-16s | %-30s | %-14s | %-24s | %6sms | ${color}%8s MB/s${RESET}\n" "$ip" "$cdn_type" "$proto" "$compat" "$ms" "$mb"
  done

  echo -e "${CYAN}==========================================================================================================${RESET}"

  # 智能去重：同机房/网段只留速度最快的冠军，并按速度排序
  if [ ${#RAW_RESULTS[@]} -gt 0 ]; then
    echo -e "\n${GREEN}🎯 最佳满血节点推荐（已自动完成同机房/网段去重，可直接复制粘贴至 hosts）：${RESET}"
    printf "%s\n" "${RAW_RESULTS[@]}" | awk -F'|' '
    {
      net = $2; spd = $3 + 0;
      if (spd > max[net]) { max[net] = spd; best[net] = $0 }
    }
    END {
      for (n in best) {
        split(best[n], arr, "|")
        print "    - " arr[1] "  # " arr[2] " 实测:" arr[3] "MB/s 握手:" arr[4] "ms"
      }
    }' | sort -k5 -r
  fi
}

# ==============================================================================
# 交互式主菜单
# ==============================================================================
clear
echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN}        NCSoft / Stove 游戏下载加速管理系统         ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo -e " 1. ${GREEN}日常巡检${RESET} (测速并精简推荐你目前常用的默认 IP 池)"
echo -e " 2. ${YELLOW}自动寻宝 (Auto)${RESET} (模拟国内三网去向 AWS 抓取最新亚太大水管)"
echo -e " 3. ${YELLOW}自定义测速${RESET} (手动输入几个新 IP 进行体检)"
echo -e " 4. ${YELLOW}新域名兼容性检测${RESET} (检查新出的游戏域名是否支持 AWS hosts)"
echo -e " 0. 退出系统"
echo -e "${CYAN}====================================================${RESET}"
read -p "请输入菜单编号 [0-4]: " choice

case "$choice" in
  1)
    echo -e "\n${CYAN}>>> 开始执行日常巡检...${RESET}"
    run_test "${DEFAULT_IPS[@]}"
    ;;
  2)
    echo -e "\n${CYAN}>>> 正在模拟【国内电信/联通/移动】向加密 DoH 抓取 AWS 候选 IP...${RESET}"
    CN_SUBNETS=("61.177.7.1" "14.17.32.1" "202.96.209.1" "210.22.84.1" "123.125.114.1" "112.90.0.1" "120.196.165.1" "183.207.224.1" "211.136.112.1")
    AUTO_IPS=($( (
      for sub in "${CN_SUBNETS[@]}"; do
        curl -s -m 4 "https://1.12.12.12/resolve?name=d1.awsstatic.com&type=A&edns_client_subnet=${sub}/24"
        curl -s -m 4 "https://223.5.5.5/resolve?name=d1.awsstatic.com&type=A&edns_client_subnet=${sub}/24"
        curl -s -m 4 "https://1.12.12.12/resolve?name=eclipse-live-down.game.playstove.com&type=A&edns_client_subnet=${sub}/24"
      done
    ) | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | cut -d'"' -f4 | sort -u ))
    echo -e "${GREEN}>>> 成功抓取到 ${#AUTO_IPS[@]} 个候选 IP，开始全自动测速过滤...${RESET}\n"
    run_test "${AUTO_IPS[@]}"
    ;;
  3)
    echo -e "\n"
    read -p "请输入你要测试的 IP (多个 IP 请用空格隔开): " -a CUSTOM_IPS
    if [ ${#CUSTOM_IPS[@]} -eq 0 ]; then
      echo "未输入任何 IP，退出。"
      exit 1
    fi
    run_test "${CUSTOM_IPS[@]}"
    ;;
  4)
    echo -e "\n"
    read -p "请输入要检测的新游戏域名 (例如: aion2-kr.download.ncupdate.com): " NEW_DOM
    if [ -z "$NEW_DOM" ]; then
      echo "未输入域名，退出。"
      exit 1
    ---
    fi
    bash /root/check_cdn.sh domain "$NEW_DOM"
    ;;
  0)
    echo "再见！"
    exit 0
    ;;
  *)
    echo "无效的选择，请输入 0-4 之间的数字。"
    ;;
esac
