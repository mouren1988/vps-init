# netfit

Linux (Debian / Ubuntu) 服务器内核网络与系统基线优化脚本。

### 核心优化项
- **内核网络**：
  - **拥塞与队列**：开启 `BBR` + `FQ` 队列算法，显式启用 TCP 时间戳 (`timestamps=1`) 与选择性确认 (`sack=1`)[cite: 6, 7]。
  - **大缓冲区**：TCP/UDP 最大读写缓冲区上限扩容至 **25MB** (`26214400`)，保留系统安全默认初始值以防小内存机 OOM[cite: 6, 7]。
  - **低延迟与防卡死**：开启 TCP Fast Open (`3`)、开启 MTU 黑洞探测 (`1`)、关闭空闲慢启动 (`slow_start_after_idle=0`)[cite: 6, 7]。
  - **高并发与端口复用**：全连接与网卡队列扩容至 `32768`、SYN 半连接队列扩容至 `16384`；开启 `TIME_WAIT` 复用、缩短回收时间至 `15s`、缩短死连接探测时间至 `600s`；本地临时出站端口池设为 `10000-65535`（保护 `10000` 以内固定服务端口不冲突）[cite: 6, 7]。
  - **转发与内存**：开启内核 IPv4 转发 (`ip_forward=1`)，降低 Swap 换出倾向 (`vm.swappiness=10`)[cite: 6, 7]。
- **连接限制**：同时解除 SSH 会话 (`limits.conf` 含 `*` 与 `root`) 与 `systemd` 后台守护进程 (`DefaultLimitNOFILE`) 的最大文件句柄限制至 `65535`[cite: 6]。
- **日志管理**：永久锁定 `systemd-journald` 系统日志上限为 `1G` (`SystemMaxUse=1G`)，满额自动滚动删旧并立即清理超标历史日志[cite: 6]。
- **系统环境**：校准系统时区为北京时间 `Asia/Shanghai` (CST)，开启 IPv4 出站优先 (`gai.conf`)[cite: 6]。

---

### 一键执行命令

bash <(curl -sL [https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh](https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh))
