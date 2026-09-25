# netfit

Linux (Debian / Ubuntu) 服务器内核网络与系统基线优化脚本。

### 核心优化项
- **内核网络**：开启 BBR + FQ，TCP/UDP 最大缓冲区扩容至 25MB (`26214400`)，开启 TFO (`3`) 与 MTU 黑洞探测，关闭空闲慢启动，本地临时端口池扩容 (`10000-65535`)，高并发队列 (`32768`)，开启 IPv4 转发。
- **连接限制**：解除单进程最大文件句柄限制 (`*` 与 `root` 均设为 `65535`)。
- **日志管理**：永久锁定 `systemd-journald` 日志上限为 `1G`，满额自动滚动清理。
- **系统环境**：校准时区为 `Asia/Shanghai` (CST)，开启 IPv4 出站优先。

### 一键执行命令

bash <(curl -sL [https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh](https://raw.githubusercontent.com/mouren1988/vps-init/main/netfit.sh))
