#!/usr/bin/env bash
# ============================================================================
# 游戏 CDN / CloudFront 直连优选工具 (极简版)
# ============================================================================

set -u

VERSION="3.9"

# 解决 bash <(curl ...) 管道运行导致 /dev/fd 虚拟路径报错的问题
DETECTED_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -z "$DETECTED_DIR" || "$DETECTED_DIR" =~ ^/dev/fd ]]; then
  WORK_DIR="$(pwd)"
else
  WORK_DIR="$DETECTED_DIR"
fi
DOMAIN_FILE="${WORK_DIR}/gmcdn_domains.conf"

# ========================== 置顶核心可调参数 ================================
# 1. 默认游戏真实测速大文件 URL (若日后官方更新安装包版本号，直接修改此行即可)
DEFAULT_GAME_TEST_URL="http://gs-purple.download.ncupdate.com/Purple/PurpleInstaller_2_25_1029_8.exe"

# 2. AWS 官方测速包 (当上方游戏安装包失效时，自动无缝切换此链接兜底)
AWS_FALLBACK_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"

# 3. 测速与筛选阈值
CONNECT_TIMEOUT=3       # 连接超时(秒)
PROBE_TIMEOUT=4         # 域名校验超时(秒)
SPEED_TIMEOUT=6         # 单个IP下载测速时长(秒)
TOP_IPS=5               # 每个域名最多保留几个 AWS 黄金 IP
MIN_SPEED_MB=10.0       # AWS 节点最低合格速度 (MB/s)

# 4. 默认待测 IP 池 (精简至实测最佳 4 节点)
DEFAULT_IPS=(
  "3.166.228.50"
  "54.239.163.107"
  "13.35.36.109"
  "99.86.18.105"
)

# 5. 内置游戏域名列表 (默认只保留 Purple 和 Stove)
BUILTIN_DOMAIN_LINES=(
  "Purple|gs-purple.download.ncupdate.com"
  "Stove|eclipsepc-dl.game.onstove.com"
)

# 国内三大运营商 ECS 骨干网段
CN_ECS_PREFIXES=(
  "61.177.7.1/24"    "14.17.32.1/24"    "202.96.209.1/24"
  "210.22.84.1/24"   "123.125.114.1/24" "112.90.0.1/24"
  "120.196.165.1/24" "183.207.224.1/24" "211.136.112.1/24"
)

DISCOVERY_ENDPOINTS=(
  "https://223.5.5.5/resolve"
  "https://1.12.12.12/resolve"
)

AWS_SEED_DOMAINS=(
  "d1.awsstatic.com"
  "eclipse-live-down.game.playstove.com"
  "eclipsepc-dl.game.onstove.com"
)

# ----------------------------- 颜色与工具 -----------------------------------
GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; CYAN="\033[36m"; BLUE="\033[34m"; RESET="\033[0m"
msg() { printf '%b\n' "$*"; }

is_ipv4() {
  local ip="$1" a b c d extra
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d extra <<< "$ip"
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
}

valid_domain() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]]
}

ms_from_sec() { awk -v x="${1:-0}" 'BEGIN { printf "%.0f", x * 1000 }'; }
mb_from_bytes_per_sec() { awk -v x="${1:-0}" 'BEGIN { printf "%.2f", x / 1048576 }'; }

extract_ipv4s() {
  grep -oE '"data"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true
}

# 核心：自动提取唯一的 /24 C段 IP，防止同机房几十个孪生 IP 拖慢测速
unique_c_class_ips() {
  tr '[:space:]' '\n' | awk 'NF && !seen[$0]++' \
    | while read -r ip; do is_ipv4 "$ip" && echo "$ip"; done \
    | awk -F'.' '{c=$1"."$2"."$3; if(!c_seen[c]++) print $0}' | sort -V
}

translate_pop() {
  local pop="$1"
  case "$pop" in
    NRT*) echo "日本/东京/amazon.com" ;;
    KIX*) echo "日本/大阪/amazon.com" ;;
    SIN*) echo "新加坡/amazon.com" ;;
    ICN*|SEL*) echo "韩国/首尔/amazon.com" ;;
    HKG*) echo "中国/香港/amazon.com" ;;
    TPE*) echo "中国/台湾/amazon.com" ;;
    *)    echo "海外/amazon.com" ;;
  esac
}

parse_url() {
  local url="$1" scheme host rest port
  scheme="${url%%://*}"; rest="${url#*://}"; host="${rest%%/*}"
  if [[ "$host" == *:* ]]; then port="${host##*:}"; host="${host%%:*}"
  elif [[ "$scheme" == "https" ]]; then port=443; else port=80; fi
  printf '%s|%s|%s\n' "$scheme" "$host" "$port"
}

# ----------------------------- 运行时数据 -----------------------------------
declare -a DOMAIN_LINES=()
declare -a TEST_IPS=()
declare -A IP_CLASS=() IP_POP=() IP_SPEED=() IP_PING=()
declare -A DOMAIN_RESULTS=()
ACTIVE_GAME_URL="$DEFAULT_GAME_TEST_URL"

ensure_domain_file() {
  [[ -f "$DOMAIN_FILE" ]] && return
  {
    echo "# 每行格式：简称|游戏下载域名"
  } > "$DOMAIN_FILE" 2>/dev/null || true
}

load_domains() {
  ensure_domain_file
  DOMAIN_LINES=("${BUILTIN_DOMAIN_LINES[@]}")
  if [[ -f "$DOMAIN_FILE" ]]; then
    local line tag dom rest
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      IFS='|' read -r tag dom rest <<< "$line"
      [[ -n "$tag" && -n "$dom" ]] && DOMAIN_LINES+=("${tag}|${dom}")
    done < "$DOMAIN_FILE"
  fi
}

load_default_ips() {
  TEST_IPS=()
  local ip
  for ip in "${DEFAULT_IPS[@]}"; do is_ipv4 "$ip" && TEST_IPS+=("$ip"); done
}

check_default_game_url() {
  local parsed scheme host port len
  parsed="$(parse_url "$DEFAULT_GAME_TEST_URL")"
  IFS='|' read -r scheme host port <<< "$parsed"
  len="$(curl --noproxy '*' -sI -m 4 --resolve "$host:$port:13.35.36.109" "$DEFAULT_GAME_TEST_URL" 2>/dev/null \
    | tr -d '\r' | awk 'tolower($1)=="content-length:" {print $2; exit}')"
  if [[ -n "$len" && "$len" -gt 1000000 ]]; then
    ACTIVE_GAME_URL="$DEFAULT_GAME_TEST_URL"
  else
    msg "${YELLOW}提示：默认游戏安装包链接已失效，本次自动切换为 AWS 官方大文件测速。${RESET}"
    ACTIVE_GAME_URL=""
  fi
}

# ----------------------------- 回源指纹校验与测速 ---------------------------
verify_payload() {
  local domain="$1" http="$2" content="$3" pop="$4"
  [[ "$http" == "000" || -z "$http" ]] && return 1

  if [[ -n "$pop" ]] || printf '%s\n' "$content" | grep -qiE '(x-amz-cf-id:|via:.*CloudFront)'; then
    if printf '%s\n' "$content" | grep -qiE '(ERROR: The request could not be satisfied|Bad request)'; then
      return 1
    fi
    [[ "$http" =~ ^(200|206|301|302|403|404)$ ]] && return 0
  fi

  case "$domain" in
    aionclive.ncupdate.com)
      [[ "$http" == "200" ]] && printf '%s\n' "$content" | grep -qiE '(c5d86b27c8a9d91|Microsoft-IIS)' && return 0
      return 1
      ;;
    *)
      printf '%s\n' "$content" | grep -qiE '(<Code>AccessDenied</Code>|Server:[[:space:]]*AmazonS3|x-amz-bucket-region:)' && return 0
      return 1
      ;;
  esac
}

probe_domain() {
  local ip="$1" domain="$2"
  local out marker http tcp pop

  out="$(curl --noproxy '*' -sS -i \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$PROBE_TIMEOUT" \
    --resolve "$domain:443:$ip" \
    -w $'\n__GMCDN__|%{http_code}|%{time_connect}\n' \
    "https://$domain/" 2>/dev/null || true)"

  marker="$(printf '%s\n' "$out" | grep '^__GMCDN__|' | tail -1 || true)"
  http="$(printf '%s' "$marker" | cut -d'|' -f2)"; [[ -n "$http" ]] || http=000
  tcp="$(printf '%s' "$marker" | cut -d'|' -f3)";  [[ -n "$tcp" ]]  || tcp=0
  pop="$(printf '%s\n' "$out" | tr -d '\r' | awk 'tolower($0) ~ /^x-amz-cf-pop:/ {print $2; exit}')"

  if verify_payload "$domain" "$http" "$out" "$pop"; then
    printf '1|%s|%s|HTTPS\n' "$(ms_from_sec "$tcp")" "$pop"
    return 0
  fi
  printf '0|0||NONE\n'
  return 1
}

speed_test() {
  local ip="$1" url="$2"
  local parsed scheme host port out marker speed tcp http
  parsed="$(parse_url "$url")"
  IFS='|' read -r scheme host port <<< "$parsed"

  out="$(curl --noproxy '*' -sS -L -o /dev/null \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$SPEED_TIMEOUT" \
    --resolve "$host:$port:$ip" \
    -w $'\n__GMSPEED__|%{speed_download}|%{time_connect}|%{http_code}\n' \
    "$url" 2>/dev/null || true)"

  marker="$(printf '%s\n' "$out" | grep '^__GMSPEED__|' | tail -1 || true)"
  speed="$(printf '%s' "$marker" | cut -d'|' -f2)"; [[ -n "$speed" ]] || speed=0
  tcp="$(printf '%s' "$marker" | cut -d'|' -f3)";   [[ -n "$tcp" ]]   || tcp=0
  http="$(printf '%s' "$marker" | cut -d'|' -f4)";  [[ -n "$http" ]]  || http=000

  if [[ "$http" != "200" && "$http" != "206" ]]; then speed=0; fi
  printf '%s|%s\n' "$(mb_from_bytes_per_sec "$speed")" "$(ms_from_sec "$tcp")"
}

test_ip_benchmark() {
  local ip="$1"
  [[ -n "${IP_CLASS[$ip]-}" ]] && return

  local out marker tcp pop
  out="$(curl --noproxy '*' -sS -I \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$PROBE_TIMEOUT" \
    --resolve "awscli.amazonaws.com:443:$ip" \
    -w $'\n__GMCDN__|%{time_connect}\n' \
    "https://awscli.amazonaws.com/" 2>/dev/null || true)"

  marker="$(printf '%s\n' "$out" | grep '^__GMCDN__|' | tail -1 || true)"
  tcp="$(printf '%s' "$marker" | cut -d'|' -f2)"; [[ -n "$tcp" ]] || tcp=0
  pop="$(printf '%s\n' "$out" | tr -d '\r' | awk 'tolower($0) ~ /^x-amz-cf-pop:/ {print $2; exit}')"

  IP_PING[$ip]="$(ms_from_sec "$tcp")"
  IP_POP[$ip]="${pop:-}"
  IP_SPEED[$ip]="0.00"

  if [[ -n "$pop" ]]; then
    IP_CLASS[$ip]="AWS"
    local target_url="${ACTIVE_GAME_URL:-$AWS_FALLBACK_URL}"
    local sr spd s_tcp
    sr="$(speed_test "$ip" "$target_url")"
    IFS='|' read -r spd s_tcp <<< "$sr"
    if [[ "$spd" == "0.00" && -n "$ACTIVE_GAME_URL" ]]; then
      sr="$(speed_test "$ip" "$AWS_FALLBACK_URL")"
      IFS='|' read -r spd s_tcp <<< "$sr"
    fi
    IP_SPEED[$ip]="${spd:-0.00}"
    [[ "$s_tcp" =~ ^[0-9]+$ && "$s_tcp" -gt 0 ]] && IP_PING[$ip]="$s_tcp"
  else
    IP_CLASS[$ip]="OTHER"
  fi
}

# ----------------------------- 核心流程 -------------------------------------
discover_ips() {
  local sdom ecs endpoint response
  local out="$(mktemp)"
  : > "$out"

  msg "${CYAN}>>> 正在通过国内三网 ECS 获取最新亚太 AWS CloudFront 节点...${RESET}"
  for sdom in "${AWS_SEED_DOMAINS[@]}"; do
    for ecs in "${CN_ECS_PREFIXES[@]}"; do
      for endpoint in "${DISCOVERY_ENDPOINTS[@]}"; do
        response="$(curl --noproxy '*' -k -sS -m 3 \
          "${endpoint}?name=${sdom}&type=A&edns_client_subnet=${ecs}" 2>/dev/null || true)"
        printf '%s\n' "$response" | extract_ipv4s >> "$out"
      done
    done
  done

  # 核心：自动提取唯一的 /24 C段代表，极大减少重复测试的时间！
  mapfile -t TEST_IPS < <(cat "$out" | unique_c_class_ips)
  rm -f "$out"

  if [[ ${#TEST_IPS[@]} -eq 0 ]]; then
    msg "${RED}>>> 未能获取到新候选 IP。${RESET}"
    return 1
  fi
  msg "${GREEN}>>> 成功提取到 ${#TEST_IPS[@]} 个不同 C段的优质候选 IP 代表！${RESET}\n"
  return 0
}

reset_runtime() {
  DOMAIN_RESULTS=()
  IP_CLASS=(); IP_POP=(); IP_SPEED=(); IP_PING=()
}

store_domain_result() {
  local domain="$1" value="$2"
  local old="${DOMAIN_RESULTS[$domain]-}"
  if [[ -n "$old" ]]; then DOMAIN_RESULTS[$domain]="${old}\n${value}"
  else DOMAIN_RESULTS[$domain]="$value"; fi
}

run_all_tests() {
  load_domains
  reset_runtime
  check_default_game_url

  local total_ips=${#TEST_IPS[@]}
  local total_doms=${#DOMAIN_LINES[@]}
  (( total_ips == 0 )) && { msg "${RED}没有可测试 IP。${RESET}"; return 1; }

  local border="======================================================================================================="
  msg "${CYAN}${border}${RESET}"
  printf "%-15s | %-36s | %-8s | %-6s | %-12s | %-s\n" \
    "IP Address" "DataCenter / Region" "Protocol" "Ping" "Speed(MB/s)" "Compatible"
  msg "${CYAN}${border}${RESET}"

  local idx=0 ip line tag domain
  for ip in "${TEST_IPS[@]}"; do
    ((idx++))
    printf '\r正在测速与校验 [%d/%d] %-15s ...' "$idx" "$total_ips" "$ip"
    test_ip_benchmark "$ip"

    local pass_cnt=0
    local any_https=0
    local bench_speed="${IP_SPEED[$ip]-0.00}"
    local cls="${IP_CLASS[$ip]-OTHER}"
    local pop="${IP_POP[$ip]-}"

    for line in "${DOMAIN_LINES[@]}"; do
      IFS='|' read -r tag domain <<< "$line"
      local probe ok tcp d_pop proto
      probe="$(probe_domain "$ip" "$domain")" || true
      IFS='|' read -r ok tcp d_pop proto <<< "$probe"

      [[ "$ok" != "1" ]] && continue
      ((pass_cnt++))
      [[ "$proto" == "HTTPS" ]] && any_https=1

      if [[ "$proto" == "HTTPS" && -z "$pop" && -n "$d_pop" ]]; then
        pop="$d_pop"; IP_POP[$ip]="$pop"; cls="AWS"; IP_CLASS[$ip]="AWS"
      fi
      [[ "${IP_PING[$ip]-0}" == "0" && "$tcp" -gt 0 ]] && IP_PING[$ip]="$tcp"

      store_domain_result "$domain" \
        "$ip|$cls|$pop|$proto|${IP_PING[$ip]-$tcp}|$bench_speed"
    done

    printf '\r%*s\r' 60 ''

    local region=""
    if [[ "$cls" == "AWS" && -n "$pop" ]]; then
      region="$(translate_pop "$pop") ($pop)"
    else
      region="第三方备用CDN"
    fi

    local proto_str="TIMEOUT"
    if (( any_https == 1 )); then proto_str="HTTPS"; fi

    local compat_str="${pass_cnt}/${total_doms}"
    local compat_color="$YELLOW"
    if (( pass_cnt == total_doms )); then
      compat_color="$GREEN"
      compat_str="${pass_cnt}/${total_doms} OK"
    elif (( pass_cnt == 0 )); then
      compat_color="$RED"
      compat_str="0/${total_doms} FAIL"
    fi

    local spd_color="$YELLOW"
    awk "BEGIN {exit !($bench_speed >= $MIN_SPEED_MB)}" && spd_color="$GREEN"
    awk "BEGIN {exit !($bench_speed < 2.0)}" && spd_color="$RED"

    printf "%-15s | %-36s | %-8s | %4sms | ${spd_color}%7s MB/s${RESET} | ${compat_color}%-10s${RESET}\n" \
      "$ip" "$region" "$proto_str" "${IP_PING[$ip]-0}" "$bench_speed" "$compat_str"
  done

  msg "${CYAN}${border}${RESET}"
}

select_for_domain() {
  local domain="$1"
  local raw="${DOMAIN_RESULTS[$domain]-}"
  [[ -n "$raw" ]] || return 0

  printf '%b\n' "$raw" | awk -F'|' -v min_spd="$MIN_SPEED_MB" '
    {
      ip=$1; cls=$2; pop=$3; proto=$4; tcp=$5+0; spd=$6+0;
      if (cls == "AWS" && spd < min_spd) next;
      if (cls != "AWS") next; # 纯净版只保留 AWS 节点
      print cls "|" spd "|" tcp "|" ip "|" pop
    }
  ' | sort -t'|' -k1,1 -k2,2nr -k3,3n | awk -F'|' -v top_n="$TOP_IPS" '
    {
      cls=$1; spd=$2; tcp=$3; ip=$4; pop=$5;
      if (pop != "" && seen_pop[pop]++) next;
      if (aws_cnt < top_n) { aws_cnt++; print ip "|" pop "|" spd }
    }
  '
}

# ----------------------------- 输出极简 hosts -------------------------------
generate_hosts() {
  echo ""
  msg "${YELLOW}hosts:${RESET}"
  msg "${YELLOW}  # === 游戏下载 CDN 自动优选配置 (完美配合 tcp-concurrent) ===${RESET}"

  local line tag domain selected
  for line in "${DOMAIN_LINES[@]}"; do
    IFS='|' read -r tag domain <<< "$line"
    selected="$(select_for_domain "$domain")"
    [[ -z "$selected" ]] && continue

    msg "${YELLOW}  '${domain}':${RESET}"
    while IFS='|' read -r ip pop spd; do
      local reg="$(translate_pop "$pop")"
      printf "${YELLOW}    - %-15s # %s (%s 实测%sMB/s)${RESET}\n" "$ip" "$reg" "$pop" "$spd"
    done <<< "$selected"
    echo ""
  done
}

add_domain() {
  ensure_domain_file
  local tag domain
  echo ""
  read -r -p "请输入游戏简称标签 (例如 L2韩服): " tag
  read -r -p "请输入游戏下载域名 (例如 l2kor.ncupdate.com): " domain

  if [[ -z "$tag" || -z "$domain" ]] || ! valid_domain "$domain"; then
    msg "${RED}域名或标签格式不正确！${RESET}"
    return 1
  fi

  if [[ -f "$DOMAIN_FILE" ]] && grep -qE "^[^|]+\|${domain//./\.}(\||$)" "$DOMAIN_FILE" 2>/dev/null; then
    msg "${YELLOW}该域名已存在，无需重复添加。${RESET}"
  else
    printf '%s|%s\n' "$tag" "$domain" >> "$DOMAIN_FILE" 2>/dev/null || true
    msg "${GREEN}>>> 已保存至配置文件！立即为你开始巡检：${RESET}\n"
  fi
  load_default_ips
  run_daily
}

show_config() {
  load_domains
  msg "\n${CYAN}--- 默认测速大文件 URL ---${RESET}"
  msg "  $DEFAULT_GAME_TEST_URL"
  msg "\n${CYAN}--- 当前监控的游戏域名 (${#DOMAIN_LINES[@]} 个) ---${RESET}"
  local line tag domain
  for line in "${DOMAIN_LINES[@]}"; do
    IFS='|' read -r tag domain <<< "$line"
    printf '  [%-8s] %s\n' "$tag" "$domain"
  done
  msg "\n${CYAN}--- 本地存储路径 ---${RESET}"
  msg "  工作目录: $WORK_DIR"
  msg "  域名配置: $DOMAIN_FILE"
}

run_daily() { 
  msg "\n${CYAN}>>> 开始默认IP检查...${RESET}"
  load_default_ips
  run_all_tests
  generate_hosts
}

run_auto() { 
  msg "\n${CYAN}>>> 开始自动优选IP (按 C段 过滤重复机房)...${RESET}"
  discover_ips || { load_default_ips; }
  run_all_tests
  generate_hosts
}

run_custom() {
  local -a custom=()
  echo ""
  read -r -p "请输入要测试的 IPv4 (多个 IP 用空格隔开): " -a custom
  [[ ${#custom[@]} -eq 0 ]] && { msg "未输入 IP。"; return 1; }
  TEST_IPS=()
  local ip
  for ip in "${custom[@]}"; do is_ipv4 "$ip" && TEST_IPS+=("$ip"); done
  run_all_tests
  generate_hosts
}

case "${1:-menu}" in
  daily) run_daily ;;
  auto)  run_auto ;;
  test)  shift; TEST_IPS=("$@"); run_all_tests; generate_hosts ;;
  add)   add_domain ;;
  show)  show_config ;;
  *)
    clear 2>/dev/null || true
    msg "${CYAN}==============================================================${RESET}"
    msg "${CYAN}         NCSoft / Stove 游戏下载 CDN 优选系统 v${VERSION}        ${RESET}"
    msg "${CYAN}==============================================================${RESET}"
    msg " 1. ${GREEN}默认IP检查${RESET}     (测试现有 4 个黄金 IP + 生成 hosts)"
    msg " 2. ${YELLOW}自动优选IP${RESET}     (通过国内三网提取最新 AWS 并智能排重)"
    msg " 3. ${YELLOW}自定义测速${RESET}   (手动输入新找到的 IP 进行体检与测速)"
    msg " 4. ${YELLOW}新增游戏域名${RESET} (永久添加新游戏域名并立即生成最新 hosts)"
    msg " 5. ${BLUE}查看当前配置${RESET} (查看已保存的游戏域名列表)"
    msg " 0. 退出"
    msg "${CYAN}==============================================================${RESET}"
    read -r -p "请输入菜单编号 [0-5]: " choice
    case "$choice" in
      1) run_daily ;;
      2) run_auto ;;
      3) run_custom ;;
      4) add_domain ;;
      5) show_config ;;
      0) exit 0 ;;
      *) msg "无效选择。" ;;
    esac
    ;;
esac
