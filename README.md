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

Debian / Ubuntu Linux 通用软件深度卸载脚本，可根据指定的软件关键词清理相关服务、进程、软件包、Docker / Podman 资源及残留文件。

## 使用方法

### 1. 预览卸载内容

先检查脚本准备处理的对象，不执行实际卸载操作。

```bash
sudo bash uninstall.sh <软件名> check
```

### 2. 确认后执行卸载

确认预览结果无误后，执行正式卸载。

```bash
sudo bash uninstall.sh <软件名>
```

将 `<软件名>` 替换为需要卸载的软件关键词，例如 `komari`。

## 主要功能

- 清理 systemd、OpenRC、SysV 等服务及相关进程
- 清理 Docker / Podman 容器、镜像、网络和卷
- 清理相关软件包、配置文件及残留文件
- 扫描本地文件系统，查找匹配的残留项
- 提供 `check` 预览模式和卸载前确认机制
- 对输入参数进行安全校验

## 注意事项

- 需要 root 权限运行。
- 建议先使用 `check` 模式检查待处理项目。
- 使用具有唯一性的**软件名称或关键词**，避免误匹配其他软件。
- 深度清理可能删除相关文件、配置或数据，请提前备份并仔细核对。
- 预览结果不代表能够完全准确地识别所有文件的归属。

---
