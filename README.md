# netfit

Linux (Debian / Ubuntu) 服务器内核网络与系统基线优化脚本。

### 核心基线项
- **内核网络 (`/etc/sysctl.d/99-netfit.conf`)**：
  - **拥塞与队列**：开启 `BBR` + `FQ` 队列算法并配置开机自动加载模块（无 BBR 内核自动回退并清理旧模块配置），显式启用 TCP 时间戳 (`timestamps=1`) 与选择性确认 (`sack=1`)[cite: 9]。
  - **大缓冲区与全局内存阈值**：TCP/UDP 单 Socket 最大读写缓冲区上限默认扩容至 **25MB** (`26214400`，低于 800MB 的小内存机型按 `RAM/32` 自动收敛)，保留系统默认初始值；并根据物理内存动态计算 `tcp_mem` 全局压力阈值（控制在物理内存的 `1/16`、`1/8`、`1/4`）[cite: 9]。
  - **连接与低延迟特性**：开启 TCP Fast Open (`3`)、开启 TCP PMTU 黑洞探测 (`1`)、关闭空闲慢启动 (`slow_start_after_idle=0`)[cite: 9]。
  - **高并发队列与端口池隔离**：全连接队列 (`somaxconn`)、SYN 半连接队列 (`tcp_max_syn_backlog`) 与网卡接收队列 (`netdev_max_backlog`) 统一设为 `16384`；开启 `TIME_WAIT` 复用、缩短 FIN 超时至 `15s`、缩短死连接探测时间至 `600s`；本地临时出站端口池设为 `10000-65535`（隔离保护 `10000` 以内固定服务端口）[cite: 9]。
  - **转发与内存策略**：开启内核 IPv4 转发 (`ip_forward=1`)，降低 Swap 换出倾向 (`vm.swappiness=10`)[cite: 9]。
- **连接数限制**：通过 `/etc/security/limits.d/99-netfit.conf` 与 `/etc/systemd/system.conf.d/99-netfit-nofile.conf` 将 PAM 会话及 `systemd` 服务默认最大文件句柄数设为 `65535`，并执行 `daemon-reexec` 重载[cite: 9]。
- **日志管理**：通过 `/etc/systemd/journald.conf.d/99-netfit-journal.conf` 永久锁定系统日志上限为 `1G` (`SystemMaxUse=1G`)，自动清理超标历史日志[cite: 9]。
- **系统策略**：统一系统时区为 `Asia/Shanghai` (CST)，并在 `/etc/gai.conf` 中设置 IPv4 优先权重为 `100`[cite: 9]。

### 一键执行命令

bash <(curl -sL [https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh](https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh))

---

# dnstool

Linux 落地机专属 SmartDNS 极速解析与守护脚本，防污染与微秒级响应优化。

### 核心特性
- **极速纯内存缓存**: 强制关闭磁盘持久化，开启自动预取保鲜 (`prefetch-domain`) 与过期缓存救急 (`serve-expired`)，实现高频域名 `0.01ms` 级解析。
- **并发测速最优解**: 开启最快响应模式 (`fastest-response`)，并发请求多路优质上游，自动返回最低延迟 IP；禁用 IPv6 解析 (`force-AAAA-SOA`) 杜绝转圈卡顿。
- **防篡改与防污染**: 支持一键切换 DoH 加密 DNS 隧道，并利用 `chattr +i` 永久锁定 `/etc/resolv.conf` 及 SmartDNS 配置文件，防止系统重启后被强制重置。
- **交互式菜单与监控**: 内置可视化操作菜单支持无缝回滚，集成 `tcpdump` 一键监听本地 DNS 解析耗时及上游预取动态。

---

# uninstall.sh

Debian / Ubuntu 通用的深度卸载清理脚本，按关键词彻底清除指定软件的进程、服务、容器及残留文件。

### 核心特性
- **全方位清理**: 自动识别并终止相关进程，清理 Systemd/SysV 服务、软件包以及 Docker/Podman 资源（容器/镜像/网络/卷）。
- **深度扫盘去留**: 扫描本地文件系统，彻底清除残留的配置文件、数据及目录。
- **安全防误删**: 内置 `check` 预览模式，真实删除前需人工二次确认，并对输入的关键词进行严格校验防止大面积误伤。

---

### 一键执行命令

> **⚠️ 注意**：请使用具有**唯一性**的软件名称，并提前做好数据备份。

建议先执行 `check` 模式预览即将清理的内容，确认无误后再进行真实卸载（将 `<软件名>` 替换为实际名称，如 `komari`）：

```bash
# 1. 安全预览模式（仅列出匹配项，不执行删除）
sudo bash uninstall.sh <软件名> check

# 2. 正式卸载模式（执行清理，中途需确认）
sudo bash uninstall.sh <软件名>
