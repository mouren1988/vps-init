# netfit

Debian / Ubuntu 服务器专属的内核网络与系统基线一键优化脚本。

### 核心特性
- **拥塞控制与低延迟**: 自动配置 `BBR` + `FQ` 算法，开启 TCP Fast Open 与 PMTU 黑洞探测，关闭空闲慢启动，大幅改善跨国网络与长连接质量。
- **高并发与大缓冲**: 动态扩容 TCP/UDP 单 Socket 缓冲区至 **25MB**（低内存机型自动智能收敛），并将全连接与半连接队列同步拉升至 `16384`，抗击突发流量洪峰。
- **端口保护与连接回收**: 划定出站端口池为 `10000-65535` 防止业务端口冲突；开启 `TIME_WAIT` 复用，并将 FIN 超时与死连接探测极限缩短，极速释放系统资源。
- **系统级资源解放**: 全局解除文件句柄限制（调整至 `65535`），永久锁定系统日志上限为 `1G` 防止爆盘；开启 IPv4 转发，并降低 Swap 依赖 (`swappiness=10`)。
- **基础环境修正**: 统一系统时区为 `Asia/Shanghai`，并设置 IPv4 优先解析权重。

---

### 一键执行命令

```bash
bash <(curl -sL [https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh](https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh))
```

---

# dnstool

Linux 落地机专属 SmartDNS 极速解析与守护脚本，防污染与微秒级响应优化。

### 核心特性
- **极速纯内存缓存**: 强制关闭磁盘持久化，开启自动预取保鲜 (`prefetch-domain`) 与过期缓存救急 (`serve-expired`)，实现高频域名 `0.01ms` 级解析。
- **并发测速最优解**: 开启最快响应模式 (`fastest-response`)，并发请求多路优质上游，自动返回最低延迟 IP；禁用 IPv6 解析 (`force-AAAA-SOA`) 杜绝转圈卡顿。
- **防篡改与防污染**: 支持一键切换 DoH 加密 DNS 隧道，并利用 `chattr +i` 永久锁定 `/etc/resolv.conf` 及 SmartDNS 配置文件，防止系统重启后被强制重置。
- **交互式菜单与监控**: 内置可视化操作菜单支持无缝回滚，集成 `tcpdump` 一键监听本地 DNS 解析耗时及上游预取动态。

---

# uninstall

Debian / Ubuntu 通用的深度卸载清理脚本，按关键词彻底清除指定软件的进程、服务、容器及残留文件。

### 核心特性
- **全方位清理**: 自动识别并终止相关进程，清理 Systemd/SysV 服务、软件包以及 Docker/Podman 资源（容器/镜像/网络/卷）。
- **深度扫盘去留**: 扫描本地文件系统，彻底清除残留的配置文件、数据及目录。
- **安全防误删**: 内置 `check` 预览模式，真实删除前需人工二次确认，并对输入的关键词进行严格校验防止大面积误伤。

---

> **⚠️ 注意**：请使用具有**唯一性**的软件名称，并提前做好数据备份。

建议先执行 `check` 模式预览即将清理的内容，确认无误后再进行真实卸载（将 `<软件名>` 替换为实际名称，如 `komari`）：

```bash
# 1. 安全预览模式（仅列出匹配项，不执行删除）
sudo bash uninstall.sh <软件名> check

# 2. 正式卸载模式（执行清理，中途需确认）
sudo bash uninstall.sh <软件名>
