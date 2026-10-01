#!/bin/bash
# 通用深度卸载脚本 - 基于 Komari 原版深度清理逻辑参数化并加固
#
# 正常执行：sudo bash uninstall.sh <软件关键词>
# 仅检查：  sudo bash uninstall.sh <软件关键词> check
#
# 注意：本脚本使用 root 权限，且第 8 步会在本地文件系统执行深度扫描。
# 对关键词的选择必须足够唯一；推荐使用软件的官方名称 / 服务名 / 安装目录名。

set +e
umask 022

say(){ printf '\n==> %s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: 必须使用 root 权限运行"
    exit 1
fi

TARGET="${1:-}"
MODE="${2:-}"

if [ -z "$TARGET" ]; then
    echo "用法："
    echo "  sudo bash $0 <软件关键词>"
    echo "  sudo bash $0 <软件关键词> check"
    echo
    echo "示例："
    echo "  sudo bash $0 komari"
    echo "  sudo bash $0 komari check"
    exit 1
fi

TARGET_LOWER="$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')"

# 只允许普通软件标识，禁止路径、空格、shell/glob/regex 元字符。
# 这样 TARGET 在 grep / awk / find / 路径拼接中的语义都可以保持为字面关键词。
if [[ ! "$TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{2,63}$ ]]; then
    echo "ERROR: 非法关键词：'$TARGET'"
    echo "只允许 3~64 个字符，且只能包含 A-Z、a-z、0-9、点、下划线、连字符；首字符必须为字母或数字。"
    exit 1
fi

# 核心系统目录 / 命令 / 常见关键基础设施名称拒绝执行。
# 这是第二层保险，不能替代“使用独特软件名”的要求。
case "$TARGET_LOWER" in
    bin|sbin|lib|lib64|lib32|libx32|libexec|usr|etc|var|opt|home|root|srv|tmp|sys|proc|dev|run|boot|media|mnt|lost+found|snap|rootfs|init|systemd|bash|sh|zsh|dash|fish|sudo|ssh|sshd|openssl|python|python3|perl|php|ruby|node|npm|docker|podman|containerd|runc|nginx|apache|httpd|mysql|mariadb|postgres|postgresql|redis|memcached)
        echo "ERROR: 关键词 '$TARGET' 属于系统关键目录、核心组件或高影响基础设施名称，已拒绝执行全盘清理。"
        exit 1
        ;;
esac

# check 是为了好记而提供的简化预览参数；-c/--check 也同时兼容。
DRY_RUN=0
case "$MODE" in
    "") ;;
    check|-c|--check) DRY_RUN=1 ;;
    *)
        echo "ERROR: 未知模式 '$MODE'。可省略，或使用 check。"
        exit 1
        ;;
esac

TMP="/tmp/.purge_$$"
UNITS="${TMP}.units"
PATHS="${TMP}.paths"
VOLS="${TMP}.vols"
ROOTS="${TMP}.roots"

: > "$UNITS"
: > "$PATHS"
: > "$VOLS"
: > "$ROOTS"

trap 'rm -f "${TMP}".* 2>/dev/null' EXIT INT TERM

# 安全打印命令，不执行。
show_cmd(){
    printf '    [CHECK]'
    printf ' %q' "$@"
    printf '\n'
}

run_cmd(){
    if [ "$DRY_RUN" -eq 1 ]; then
        show_cmd "$@"
        return 0
    fi
    "$@"
}

rm_f(){
    if [ "$DRY_RUN" -eq 1 ]; then
        show_cmd rm -f -- "$@"
    else
        rm -f -- "$@" 2>/dev/null || true
    fi
}

rm_rf(){
    if [ "$DRY_RUN" -eq 1 ]; then
        show_cmd rm -rf -- "$@"
    else
        rm -rf -- "$@" 2>/dev/null || true
    fi
}

TARGET_SED="${TARGET//./\\.}"

edit_delete_lines(){
    local f="$1"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [CHECK] 将从文件删除包含 '$TARGET' 的行: $f"
    else
        # TARGET 已限制为安全字符；仅需把点转义，避免 sed 将其当作任意字符。
        sed -i "/${TARGET_SED}/Id" "$f" 2>/dev/null || true
    fi
}

# 当前脚本真实路径；用于避免全盘/配置核验时把脚本自身当成残留。
SCRIPT_PATH="$(readlink -f -- "$0" 2>/dev/null)"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "=============================================="
    echo "CHECK MODE：仅检查，不停止服务、不杀进程、不删除文件、不卸载软件包。"
    echo "目标关键词：$TARGET"
    echo "=============================================="
else
    echo "=============================================="
    echo "警告：此脚本使用 root 权限执行深度卸载，并包含本地文件系统全盘扫描删除。"
    echo "目标关键词：$TARGET"
    echo
    echo "执行前确认："
    echo "  1. TARGET 应是足够唯一的软件名称。"
    echo "  2. 关键词过于宽泛可能匹配到其他服务、进程、包或文件。"
    echo "  3. 建议先运行：sudo bash $0 $TARGET check"
    echo
    printf "请输入目标关键词 '%s' 以确认继续，或按 Ctrl+C 取消： " "$TARGET"
    IFS= read -r CONFIRM
    if [ "$CONFIRM" != "$TARGET" ]; then
        echo "已取消。"
        exit 1
    fi
    echo "确认通过，开始执行。"
    sleep 1
fi

###############################################################################
# 1. 停止并删除服务
###############################################################################

say "1/10 停止并删除服务"

if have systemctl; then
    # systemd：扫描服务内容并记录自定义 WorkingDirectory。
    for d in /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
        [ -d "$d" ] || continue
        find "$d" -type f \
            \( -name '*.service' -o -name '*.timer' -o -name '*.socket' -o -name '*.path' \) \
            -print 2>/dev/null |
        while IFS= read -r f; do
            if grep -Fqi -- "$TARGET" "$f" 2>/dev/null; then
                echo "    发现 systemd 定义: $f"
                echo "$f" >> "$UNITS"
                sed -n 's/^[[:space:]]*WorkingDirectory[[:space:]]*=[[:space:]]*//p' "$f" 2>/dev/null |
                    sed 's/^[-+]//' |
                    tr -d "\"'" >> "$PATHS"
            fi
        done
    done

    # 服务名称本身包含 TARGET。
    systemctl list-unit-files --no-legend --no-pager 2>/dev/null |
        awk '{print $1}' |
        grep -Fii -- "$TARGET" 2>/dev/null |
        while IFS= read -r u; do
            [ -n "$u" ] || continue
            echo "    停止服务: $u"
            run_cmd systemctl stop "$u" 2>/dev/null || true
            run_cmd systemctl disable "$u" 2>/dev/null || true
        done

    # 删除从内容识别出来的服务定义。
    sort -u "$UNITS" 2>/dev/null |
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        u="$(basename "$f")"
        echo "    删除 systemd 服务: $u"
        run_cmd systemctl stop "$u" 2>/dev/null || true
        run_cmd systemctl disable "$u" 2>/dev/null || true
        rm_f "$f"
    done
fi

###############################################################################
# OpenRC / procd / SysV
###############################################################################

if [ -d /etc/init.d ]; then
    for f in /etc/init.d/*; do
        [ -f "$f" ] || continue
        b="$(basename "$f")"
        if printf '%s\n' "$b" | grep -Fqi -- "$TARGET" || grep -Fqi -- "$TARGET" "$f" 2>/dev/null; then
            echo "    删除 init 服务: $b"
            sed -n 's/^[[:space:]]*directory[[:space:]]*=[[:space:]]*//p' "$f" 2>/dev/null |
                tr -d "\"'" >> "$PATHS"
            run_cmd "$f" stop 2>/dev/null || true
            run_cmd "$f" disable 2>/dev/null || true
            if have rc-update; then
                run_cmd rc-update del "$b" default 2>/dev/null || true
            fi
            rm_f "$f"
        fi
    done
fi

###############################################################################
# Upstart（原版逻辑完整保留）
###############################################################################

if [ -d /etc/init ]; then
    find /etc/init -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null |
    while IFS= read -r f; do
        b="$(basename "$f" .conf)"
        if printf '%s\n' "$b" | grep -Fqi -- "$TARGET" || grep -Fqi -- "$TARGET" "$f" 2>/dev/null; then
            sed -n 's/^[[:space:]]*chdir[[:space:]]\+//p' "$f" 2>/dev/null |
                tr -d "\"'" >> "$PATHS"
            if have initctl; then
                run_cmd initctl stop "$b" 2>/dev/null || true
            fi
            echo "    删除 Upstart 服务: $b"
            rm_f "$f"
        fi
    done
fi

###############################################################################
# 2. Docker
###############################################################################

say "2/10 清理 Docker"

if have docker; then
    docker ps -a --format '{{.ID}}\t{{.Image}}\t{{.Names}}' 2>/dev/null |
        awk -v t="$TARGET_LOWER" 'index(tolower($0), t) > 0 {print $1}' |
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            echo "    删除 Docker 容器: $id"
            docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' "$id" 2>/dev/null >> "$VOLS" || true
            if [ "$DRY_RUN" -eq 1 ]; then
                show_cmd docker rm -fv "$id"
                show_cmd docker rm -f "$id"
            else
                docker rm -fv "$id" 2>/dev/null || docker rm -f "$id" 2>/dev/null || true
            fi
        done

    docker volume ls --format '{{.Name}}' 2>/dev/null |
        grep -Fii -- "$TARGET" 2>/dev/null >> "$VOLS" || true

    sort -u "$VOLS" 2>/dev/null |
    while IFS= read -r v; do
        [ -n "$v" ] || continue
        echo "    删除 Docker Volume: $v"
        if [ "$DRY_RUN" -eq 1 ]; then
            show_cmd docker volume rm -f "$v"
            show_cmd docker volume rm "$v"
        else
            docker volume rm -f "$v" 2>/dev/null || docker volume rm "$v" 2>/dev/null || true
        fi
    done

    docker network ls --format '{{.Name}}' 2>/dev/null |
        grep -Fii -- "$TARGET" 2>/dev/null |
        while IFS= read -r n; do
            [ -n "$n" ] || continue
            echo "    删除 Docker Network: $n"
            run_cmd docker network rm "$n" 2>/dev/null || true
        done

    docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null |
        awk -v t="$TARGET_LOWER" 'index(tolower($1), t) > 0 {print $2}' |
        sort -u |
        while IFS= read -r img; do
            [ -n "$img" ] || continue
            echo "    删除 Docker Image: $img"
            run_cmd docker rmi -f "$img" 2>/dev/null || true
        done
fi

###############################################################################
# 3. Podman
###############################################################################

say "3/10 清理 Podman"

if have podman; then
    podman ps -a --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null |
        awk -v t="$TARGET_LOWER" 'index(tolower($0), t) > 0 {print $1}' |
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            echo "    删除 Podman 容器: $id"
            if [ "$DRY_RUN" -eq 1 ]; then
                show_cmd podman rm -f -v "$id"
                show_cmd podman rm -f "$id"
            else
                podman rm -f -v "$id" 2>/dev/null || podman rm -f "$id" 2>/dev/null || true
            fi
        done

    podman volume ls --format '{{.Name}}' 2>/dev/null |
        grep -Fii -- "$TARGET" 2>/dev/null |
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            echo "    删除 Podman Volume: $v"
            if [ "$DRY_RUN" -eq 1 ]; then
                show_cmd podman volume rm -f "$v"
                show_cmd podman volume rm "$v"
            else
                podman volume rm -f "$v" 2>/dev/null || podman volume rm "$v" 2>/dev/null || true
            fi
        done

    podman network ls --format '{{.Name}}' 2>/dev/null |
        grep -Fii -- "$TARGET" 2>/dev/null |
        while IFS= read -r n; do
            [ -n "$n" ] || continue
            echo "    删除 Podman Network: $n"
            if [ "$DRY_RUN" -eq 1 ]; then
                show_cmd podman network rm -f "$n"
                show_cmd podman network rm "$n"
            else
                podman network rm -f "$n" 2>/dev/null || podman network rm "$n" 2>/dev/null || true
            fi
        done

    podman images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null |
        awk -v t="$TARGET_LOWER" 'index(tolower($1), t) > 0 {print $2}' |
        sort -u |
        while IFS= read -r img; do
            [ -n "$img" ] || continue
            echo "    删除 Podman Image: $img"
            run_cmd podman rmi -f "$img" 2>/dev/null || true
        done
fi

###############################################################################
# 4. 安全杀掉目标进程
###############################################################################

say "4/10 终止所有残余进程"

kill_target()
{
    local sig="$1"

    for p in /proc/[0-9]*; do
        [ -r "$p/cmdline" ] || continue

        local pid="${p##*/}"
        [ "$pid" = "$$" ] && continue
        [ "$pid" = "$PPID" ] && continue

        local exe="$(readlink -f "$p/exe" 2>/dev/null)"
        local cmd="$(tr '\000' ' ' < "$p/cmdline" 2>/dev/null)"
        local matched=0

        if printf '%s\n%s\n' "$exe" "$cmd" | grep -Fqi -- "$TARGET"; then
            matched=1
        fi

        # 原版关键能力：如果程序本身不带目标名称，则按服务发现到的自定义安装目录判断。
        if [ "$matched" -eq 0 ] && [ -n "$exe" ] && [ -s "$PATHS" ]; then
            while IFS= read -r d; do
                d="${d%/}"
                [ -n "$d" ] || continue
                case "$exe" in
                    "$d"/*)
                        matched=1
                        break
                        ;;
                esac
            done < "$PATHS"
        fi

        if [ "$matched" -eq 1 ]; then
            echo "    kill -$sig PID $pid -> ${exe:-$cmd}"
            run_cmd kill "-$sig" "$pid" 2>/dev/null || true
        fi
    done
}

kill_target TERM
if [ "$DRY_RUN" -eq 0 ]; then sleep 1; fi
kill_target KILL

###############################################################################
# 5. 包管理器 + 常见目录
###############################################################################

say "5/10 删除程序、数据库、配置、日志、备份"

# Debian / Ubuntu
if have dpkg-query; then
    mapfile -t pkgs < <(
        dpkg-query -W -f='${binary:Package}\n' 2>/dev/null |
        grep -Fii -- "$TARGET" || true
    )

    if [ "${#pkgs[@]}" -gt 0 ]; then
        printf '    Debian 候选软件包: '
        printf '%s ' "${pkgs[@]}"
        printf '\n'

        if [ "$DRY_RUN" -eq 1 ]; then
            show_cmd env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}"
            echo "    [CHECK] 若 apt purge 失败，原逻辑还会尝试 dpkg --purge。"
        else
            DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}" 2>/dev/null ||
                dpkg --purge "${pkgs[@]}" 2>/dev/null || true
        fi
    fi

# CentOS / Rocky / Alma / Fedora
elif have rpm; then
    mapfile -t pkgs < <(
        rpm -qa 2>/dev/null |
        grep -Fii -- "$TARGET" || true
    )

    if [ "${#pkgs[@]}" -gt 0 ]; then
        printf '    RPM 候选软件包: '
        printf '%s ' "${pkgs[@]}"
        printf '\n'

        if have dnf; then
            run_cmd dnf -y remove "${pkgs[@]}" 2>/dev/null || true
        elif have yum; then
            run_cmd yum -y remove "${pkgs[@]}" 2>/dev/null || true
        else
            run_cmd rpm -e "${pkgs[@]}" 2>/dev/null || true
        fi
    fi

# Alpine
elif have apk; then
    mapfile -t pkgs < <(
        apk info 2>/dev/null |
        grep -Fii -- "$TARGET" || true
    )

    if [ "${#pkgs[@]}" -gt 0 ]; then
        printf '    APK 候选软件包: '
        printf '%s ' "${pkgs[@]}"
        printf '\n'
        run_cmd apk del "${pkgs[@]}" 2>/dev/null || true
    fi
fi

# 常见 Agent / 主控 / 备份 / 数据目录等。
# TARGET 已限制字符集，因此这里不会发生路径穿越或 glob 注入。
for prefix in /opt /usr/local /etc /var/lib /var/log /var/cache /tmp /var/tmp; do
    rm_rf "${prefix}/${TARGET}" "${prefix}/${TARGET}-"* "${prefix}/"*"${TARGET_LOWER}"*
done

for binpath in /usr/bin /usr/local/bin /usr/sbin /usr/local/sbin; do
    rm_f "${binpath}/${TARGET}" "${binpath}/${TARGET}-"*
done

###############################################################################
# 删除服务定义中发现的自定义安装目录
###############################################################################

sort -u "$PATHS" 2>/dev/null |
while IFS= read -r p; do
    p="${p%/}"
    [ -n "$p" ] || continue

    # 原版保护清单。
    case "$p" in
        /|/bin|/sbin|/lib|/lib64|/usr|/usr/bin|/usr/sbin|/usr/lib|/usr/lib64|\
        /usr/local|/etc|/var|/opt|/home|/root|/srv|/tmp|/var/tmp)
            continue
            ;;
    esac

    case "$p" in
        /*)
            # 如果 realpath 可用，进一步阻止 /foo/../etc 之类的规范化路径越界。
            check_path="$p"
            if have realpath; then
                check_path="$(realpath -m -- "$p" 2>/dev/null)"
            fi
            case "$check_path" in
                /|/bin|/sbin|/lib|/lib64|/usr|/usr/bin|/usr/sbin|/usr/lib|/usr/lib64|\
                /usr/local|/etc|/var|/opt|/home|/root|/srv|/tmp|/var/tmp)
                    echo "    跳过受保护自定义目录: $p"
                    continue
                    ;;
            esac

            if [ -e "$p" ] || [ -L "$p" ]; then
                echo "    删除自定义安装目录: $p"
                rm_rf "$p"
            fi
            ;;
    esac
done

###############################################################################
# 6. 用户级安装 / shell history / cron
###############################################################################

say "6/10 清理用户级安装、历史记录和定时任务"

{
    echo /root
    if have getent; then
        getent passwd 2>/dev/null | awk -F: '$6 ~ /^\// {print $6}'
    else
        awk -F: '$6 ~ /^\// {print $6}' /etc/passwd 2>/dev/null
    fi
} | sort -u |
while IFS= read -r h; do
    [ -d "$h" ] || continue

    rm_rf \
        "$h/.local/share/$TARGET" \
        "$h/.$TARGET"

    ###########################################################################
    # 用户级 systemd
    ###########################################################################

    if [ -d "$h/.config/systemd/user" ]; then
        find "$h/.config/systemd/user" \
            -maxdepth 3 \
            -type f \
            -name '*.service' \
            -print 2>/dev/null |
        while IFS= read -r uf; do
            if printf '%s\n' "$(basename "$uf")" | grep -Fqi -- "$TARGET" ||
               grep -Fqi -- "$TARGET" "$uf" 2>/dev/null
            then
                sed -n 's/^[[:space:]]*WorkingDirectory[[:space:]]*=[[:space:]]*//p' "$uf" 2>/dev/null |
                    sed 's/^[-+]//' |
                    tr -d "\"'" >> "$PATHS"

                unit="$(basename "$uf")"
                uid="$(stat -c %u "$h" 2>/dev/null)"
                owner="$(stat -c %U "$h" 2>/dev/null)"

                if [ -n "$uid" ] && [ -d "/run/user/$uid" ] && have runuser && [ -n "$owner" ]; then
                    run_cmd runuser -u "$owner" -- \
                        env XDG_RUNTIME_DIR="/run/user/$uid" \
                        systemctl --user disable --now "$unit" 2>/dev/null || true
                fi

                echo "    删除用户服务: $uf"
                rm_f "$uf"
            fi
        done
    fi

    ###########################################################################
    # Shell 历史
    ###########################################################################

    for hf in \
        "$h/.bash_history" \
        "$h/.zsh_history" \
        "$h/.ash_history" \
        "$h/.sh_history"
    do
        [ -f "$hf" ] || continue
        edit_delete_lines "$hf"
    done

    ###########################################################################
    # 用户环境配置
    ###########################################################################

    for cf in \
        "$h/.bashrc" \
        "$h/.bash_profile" \
        "$h/.profile" \
        "$h/.zshrc"
    do
        [ -f "$cf" ] || continue
        edit_delete_lines "$cf"
    done
done

# 再杀一次用户级 / 自定义目录进程
kill_target TERM
if [ "$DRY_RUN" -eq 0 ]; then sleep 1; fi
kill_target KILL

# 删除刚发现的用户级自定义安装目录
sort -u "$PATHS" 2>/dev/null |
while IFS= read -r p; do
    p="${p%/}"
    [ -n "$p" ] || continue

    case "$p" in
        /|/bin|/sbin|/lib|/lib64|/usr|/usr/bin|/usr/sbin|/usr/lib|/usr/lib64|\
        /usr/local|/etc|/var|/opt|/home|/root|/srv|/tmp|/var/tmp)
            continue
            ;;
    esac

    case "$p" in
        /*)
            check_path="$p"
            if have realpath; then
                check_path="$(realpath -m -- "$p" 2>/dev/null)"
            fi
            case "$check_path" in
                /|/bin|/sbin|/lib|/lib64|/usr|/usr/bin|/usr/sbin|/usr/lib|/usr/lib64|\
                /usr/local|/etc|/var|/opt|/home|/root|/srv|/tmp|/var/tmp)
                    continue
                    ;;
            esac
            echo "    删除用户级自定义目录: $p"
            rm_rf "$p"
            ;;
    esac
done

###############################################################################
# Cron / environment
###############################################################################

for f in \
    /etc/crontab \
    /etc/environment \
    /etc/profile \
    /etc/bash.bashrc
do
    [ -f "$f" ] || continue
    edit_delete_lines "$f"
done

for d in \
    /etc/cron.d \
    /var/spool/cron \
    /var/spool/cron/crontabs
do
    [ -d "$d" ] || continue
    find "$d" \
        -maxdepth 2 \
        -type f \
        -print 2>/dev/null |
    while IFS= read -r f; do
        edit_delete_lines "$f"
    done
done

###############################################################################
# 7. 删除目标用户/组
###############################################################################

say "7/10 删除目标系统用户和组"

if have loginctl; then
    run_cmd loginctl disable-linger "$TARGET_LOWER" 2>/dev/null || true
fi

if id "$TARGET_LOWER" >/dev/null 2>&1; then
    echo "    删除用户: $TARGET_LOWER"
    if have userdel; then
        if [ "$DRY_RUN" -eq 1 ]; then
            show_cmd userdel -r "$TARGET_LOWER"
            show_cmd userdel "$TARGET_LOWER"
        else
            userdel -r "$TARGET_LOWER" 2>/dev/null || userdel "$TARGET_LOWER" 2>/dev/null || true
        fi
    elif have deluser; then
        if [ "$DRY_RUN" -eq 1 ]; then
            show_cmd deluser --remove-home "$TARGET_LOWER"
            show_cmd deluser "$TARGET_LOWER"
        else
            deluser --remove-home "$TARGET_LOWER" 2>/dev/null || deluser "$TARGET_LOWER" 2>/dev/null || true
        fi
    fi
fi

if have getent && getent group "$TARGET_LOWER" >/dev/null 2>&1; then
    echo "    删除组: $TARGET_LOWER"
    if have groupdel; then
        run_cmd groupdel "$TARGET_LOWER" 2>/dev/null || true
    elif have delgroup; then
        run_cmd delgroup "$TARGET_LOWER" 2>/dev/null || true
    fi
fi

###############################################################################
# 8. 本地磁盘全盘扫描
###############################################################################

say "8/10 全盘删除名称中包含 $TARGET 的残留"

if have findmnt; then
    findmnt -rn -o TARGET,FSTYPE 2>/dev/null |
    while read -r target fstype; do
        case "$fstype" in
            proc|sysfs|devtmpfs|devpts|tmpfs|cgroup|cgroup2|pstore|securityfs|debugfs|tracefs|configfs|mqueue|hugetlbfs|rpc_pipefs|nfs|nfs4|cifs|smb3|sshfs|9p|fuse|fuse.*|autofs|nsfs)
                continue
                ;;
            overlay)
                [ "$target" = "/" ] || continue
                ;;
        esac
        echo "$target"
    done > "$ROOTS"
fi

[ -s "$ROOTS" ] || echo "/" > "$ROOTS"

sort -u "$ROOTS" |
while IFS= read -r root; do
    [ -d "$root" ] || continue

    find "$root" \
        -xdev \
        -depth \
        -iname "*${TARGET}*" \
        -not -path "$SCRIPT_PATH" \
        -print 2>/dev/null |
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        echo "    删除: $p"
        rm_rf "$p"
    done
done

###############################################################################
# 9. 刷新服务
###############################################################################

say "9/10 刷新系统服务状态"

if have systemctl; then
    run_cmd systemctl daemon-reload 2>/dev/null || true
    run_cmd systemctl reset-failed 2>/dev/null || true
fi

if have initctl; then
    run_cmd initctl reload-configuration 2>/dev/null || true
fi

# PID 文件名不是执行对象，因此仍保留原版通配形式；TARGET 已经过安全字符集限制。
rm_f \
    /run/${TARGET}*.pid \
    /run/*${TARGET_LOWER}*.pid

###############################################################################
# 10. 最终核验
###############################################################################

# 判断 PID 是否为当前脚本或其祖先进程。
# 这样 standalone 脚本的命令行中即使出现 TARGET，也不会被误判为残余进程。
is_self_or_ancestor() {
    local candidate="$1"
    local cur="$$"
    local seen=0
    while [ -n "$cur" ] && [ "$cur" -gt 1 ] 2>/dev/null && [ "$seen" -lt 64 ]; do
        if [ "$candidate" = "$cur" ]; then
            return 0
        fi
        cur="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
        seen=$((seen + 1))
    done
    return 1
}

say "10/10 最终核验 ($TARGET)"

FOUND=0

echo
echo "========== PROCESS =========="
while read -r pid user comm args; do
    [ -n "$pid" ] || continue
    if is_self_or_ancestor "$pid"; then
        continue
    fi
    if printf '%s\n%s\n' "$comm" "$args" | grep -Fi -- "$TARGET"; then
        printf '%s %s %s %s\n' "$pid" "$user" "$comm" "$args"
        FOUND=1
    fi
done < <(ps -eo pid=,user=,comm=,args= 2>/dev/null)

echo
echo "========== SYSTEMD =========="
if have systemctl; then
    if systemctl list-unit-files --no-pager 2>/dev/null | grep -Fi -- "$TARGET"; then
        FOUND=1
    fi
    if systemctl list-units --all --no-pager 2>/dev/null | grep -Fi -- "$TARGET"; then
        FOUND=1
    fi
fi

echo
echo "========== DOCKER =========="
if have docker; then
    if docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
    if docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
    if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
fi

echo
echo "========== PODMAN =========="
if have podman; then
    if podman ps -a --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
    if podman images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
    if podman volume ls --format '{{.Name}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
    if podman network ls --format '{{.Name}}' 2>/dev/null | grep -Fi -- "$TARGET"; then FOUND=1; fi
fi

echo
echo "========== FILES =========="
: > "${TMP}.left"
sort -u "$ROOTS" 2>/dev/null |
while IFS= read -r root; do
    [ -d "$root" ] || continue
    find "$root" -xdev -iname "*${TARGET}*" -not -path "$SCRIPT_PATH" -print 2>/dev/null
done > "${TMP}.left"

if [ -s "${TMP}.left" ]; then
    cat "${TMP}.left"
    FOUND=1
fi

echo
echo "========== CONFIG REFERENCES =========="
: > "${TMP}.refs"
for d in /etc /usr/local/etc /root /home; do
    [ -e "$d" ] || continue
    grep -RIl \
        --exclude='*.journal' \
        --exclude='*.db' \
        --exclude='*.sqlite*' \
        --exclude='*.tar*' \
        --exclude='*.gz' \
        --exclude='*.zip' \
        -i -F -- "$TARGET" \
        "$d" 2>/dev/null >> "${TMP}.refs" || true
done

if [ -n "$SCRIPT_PATH" ]; then
    grep -Fvx -- "$SCRIPT_PATH" "${TMP}.refs" > "${TMP}.refs.sorted" 2>/dev/null || : > "${TMP}.refs.sorted"
else
    sort -u "${TMP}.refs" > "${TMP}.refs.sorted" 2>/dev/null
fi
sort -u "${TMP}.refs.sorted" -o "${TMP}.refs.sorted" 2>/dev/null || true
if [ -s "${TMP}.refs.sorted" ]; then
    cat "${TMP}.refs.sorted"
    FOUND=1
fi

echo
echo "=============================================="
if [ "$FOUND" -eq 0 ]; then
    echo "PASS"
    echo "未检测到 $TARGET 进程、服务、Docker/Podman、文件或配置残留。"
else
    echo "CHECK"
    echo "上方仍检测到疑似 $TARGET 残留，请检查对应条目。"
fi
echo "=============================================="

# 对当前 Bash 子进程的 history 进行尝试；单独 sudo/bash 启动时不能修改父交互 shell 的 history。
if [ "$DRY_RUN" -eq 0 ] && [ -n "${BASH_VERSION:-}" ]; then
    while :; do
        n="$(history 2>/dev/null | grep -Fi -- "$TARGET" | tail -n 1 | awk '{print $1}')"
        [ -n "$n" ] || break
        history -d "$n" 2>/dev/null || break
    done
    history -w 2>/dev/null || true
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "CHECK 完成：以上仅为检查/模拟动作，没有执行卸载。"
fi
