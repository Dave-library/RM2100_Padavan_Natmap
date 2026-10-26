# natmap 端口映射与自动维护系统

> 专为小米/红米路由器（Padavan/老毛子固件）设计的 NAT 穿透与自动维护方案，支持端口映射、进程保活、防火墙自动修复、微信推送和日志轮转。

![平台](https://img.shields.io/badge/platform-Padavan-blue)
![版本](https://img.shields.io/badge/version-v1.0-green)
![状态](https://img.shields.io/badge/status-stable-success)

---

## 项目简介

- 历经多次版本迭代，最终于 **2026-07-15** 完成上线，稳定运行**4个月**，无异常问题。
- 由于 RM2100 的 Padavan 系统分配的永久性存储空间较小，脚本内置日志轮转机制：**每 7 天或超过 1MB 自动清理日志**。
- 本项目仅涉及 **natmap** 功能。微信测试号推送与域名映射需参考其他教程。
- 脚本内容由 DeepSeek 辅助生成，**下载使用前请将内网 IP、端口替换为自己的实际配置**。
- 适用于当前环境无**公网IPv4**需要访问**私网IPv4**的情况。
- 微信测试号推送中会显示三个地址：外网访问使用「**公网地址:端口**」，路由器侧防火墙规则需添加「**出口地址:端口**」。
- natmap二进制源文件来源[**heiher/natmap**](https://github.com/heiher/natmap)，其他shell脚本文件由[**deepseek网页版**](https://chat.deepseek.com/)辅助生成。

### 效果展示
*微信推送效果*[br/]
[![微信推送效果](images/wechat-push.png)](https://github.com/Dave-library/RM2100_Padavan_Natmap)[br/][br/]
*域名访问效果*[br/]
[![域名访问效果](images/domain-name-access.png)](https://github.com/Dave-library/RM2100_Padavan_Natmap)[br/]

                                       

---

## 目录

- [系统概述](#系统概述)
- [快速部署](#快速部署)
- [目录结构](#目录结构)
- [脚本说明](#脚本说明)
- [微信推送](#微信推送)
- [Web 配置](#web-配置)
- [手动命令](#手动命令)
- [日志与轮转](#日志与轮转)
- [STUN 服务器](#stun-服务器)
- [故障排查](#故障排查)
- [扩展与自定义](#扩展与自定义)
- [注意事项](#注意事项)
- [版本信息](#版本信息)

---

## 系统概述

通过 `natmap` 实现 NAT 穿透（打洞），将内网服务（路由器自身、NAS）的端口映射到公网，并自动维护整个流程的稳定性。

### 核心功能

1. 实时监控 WAN IP 变化，每 30 秒检测，变化时自动重启 natmap
2. 进程保活：natmap 和监控脚本崩溃后自动恢复（6 小时冷却防频繁重试）
3. 防火墙自动管理：端口变化时增删 INPUT 规则，规则被误删后 15 秒内补回
4. NAS 时段控制：仅周五 18:00 至周日 24:00 运行，其余时间自动停止
5. 微信推送：更新成功/失败、IP 变化原因、服务不可达等实时通知
6. 日志轮转：每天 4:00 清理超 7 天或超 1MB 的日志文件

### 内网 IP 规划

| 服务 | 内网地址 | 说明 |
|------|----------|------|
| ROUTER | `172.16.10.1:5001` | 路由器自身 |
| NAS | `172.16.10.99:5001` | 内网 NAS 设备 |

---

## 快速部署

### 1. 上传脚本并赋权

```bash
chmod +x /etc/storage/bin/natmap/*.sh
chmod +x /etc/storage/bin/natmap/*/monitor_*.sh
chmod +x /etc/storage/bin/natmap/*/start_*.sh
chmod +x /etc/storage/bin/natmap/*/stop_*.sh
chmod +x /etc/storage/bin/natmap/natmap
```

### 2. 配置微信推送

编辑 `/etc/storage/script/Sh45_wx_send.sh`，提前配置好测试号或 Webhook。

### 3. 添加开机启动

路由器 Web 后台 → **高级设置 → 参数设置 → 脚本** → **在路由器启动后执行**，添加：

```bash
/etc/storage/bin/natmap/check_ip_change.sh &
```

### 4. 添加关机清理

**在路由器关闭之前执行**，添加：

```bash
/etc/storage/bin/natmap/router/stop_router.sh
/etc/storage/bin/natmap/nas/stop_nas.sh
```

### 5. 手动启动测试（可选）

```bash
/etc/storage/bin/natmap/check_ip_change.sh &
tail -f /etc/storage/bin/natmap/router/logs/router_ip_monitor.log
```

---

## 目录结构

```text
/etc/storage/bin/natmap/            主目录
├── check_ip_change.sh              主监控脚本（常驻后台）
├── natmap                          natmap 二进制程序
├── router/                         ROUTER 服务目录
│   ├── monitor_router.sh           端口监控（解析日志、管理防火墙、推送）
│   ├── start_router.sh             启动脚本
│   ├── stop_router.sh              停止脚本
│   └── logs/
│       ├── router_ip_monitor.log   主控日志
│       ├── router_natmap.log       natmap 输出日志
│       └── router_debug.log        monitor 调试日志
└── nas/                            NAS 服务目录（结构相同）
    ├── monitor_nas.sh
    ├── start_nas.sh
    ├── stop_nas.sh
    └── logs/
```

---

## 脚本说明

### check_ip_change.sh（主监控脚本）

- 每 30 秒获取一次稳定的 WAN IP
- IP 变化时重启对应服务的 natmap
- 保活检测：若 natmap 或 monitor 进程缺失，自动拉起
- NAS 时段控制：只在周五 18:00 ~ 周日 24:00 允许运行
- 每日 4:00 ~ 4:05 执行日志轮转
- 内网 IP 不可达时发送微信告警，进入 6 小时冷却
- 将 IP 变化原因写入 `/tmp/ip_change_reason_router` 和 `/tmp/ip_change_reason_nas`

启动方式：

```bash
nohup /etc/storage/bin/natmap/check_ip_change.sh > /dev/null 2>&1 &
```

### monitor_router.sh / monitor_nas.sh（端口监控）

- 监控对应的 `*_natmap.log`，提取最新公网 IP 和端口
- 检测到端口变化时，等待 20 秒确认稳定
- 更新防火墙规则（删除旧端口，添加新端口）
- 将当前端口写入 `/tmp/natmap_router_port`（或 nas）
- 发送微信推送，标题区分 `[ROUTER]` 或 `[NAS]`
- 每 15 秒巡检防火墙规则，缺失时自动补充

锁文件：`/tmp/monitor_router.lock` 和 `/tmp/monitor_nas.lock`

### start_router.sh / start_nas.sh（启动脚本）

- ping 目标内网 IP，不可达则退出并微信告警
- 启动 natmap（若未运行）
- 启动 monitor 脚本（若未运行）

> **注意**：日常保活由 `check_ip_change.sh` 负责，本脚本仅用于首次启动或手动调试。开机时不要执行，否则拨号未完成会误报警告。

### stop_router.sh / stop_nas.sh（停止脚本）

- 从 `/tmp/natmap_router_port` 读取当前端口并删除规则
- 从对应的 `*_natmap.log` 提取所有历史端口并删除
- 停止 natmap 和 monitor 进程
- 删除锁文件

### natmap（核心二进制）

```bash
natmap -d -s turn.cloudflare.com -h baidu.com -b 0 -t <内网IP> -p 5001
```

| 参数 | 说明 |
|------|------|
| `-d` | 守护进程模式 |
| `-s` | STUN 服务器 |
| `-h` | 心跳检测域名 |
| `-b 0` | 绑定所有接口 |
| `-t` | 目标内网 IP |
| `-p` | 目标端口（固定 5001） |

输出格式示例：

```text
2026-06-20 00:12:15 203.0.113.5 43536 172.16.10.1 63964 tcp 172.16.10.1
```

列含义：日期 时间 公网IP 公网端口 内网IP 本地端口 协议 目标IP

---

## 微信推送

### IP 变化触发

| 场景 | 推送原因 |
|------|----------|
| 凌晨 3:00 定时重启 | 定时重启（凌晨 3:00） |
| 手动重启（SSH/Web） | 手动重启（SSH/Web 触发） |
| PPPoE 断线重连 | 网络断线重连（PPPoE 链路中断） |
| 凌晨 2:00~5:00 重拨 | 运营商例行维护（凌晨时段重拨） |
| 其他 | 外网链路变化，重新拨号 |

### 端口变化触发

若 120 秒内有 IP 变化原因，则复用该原因；否则使用「端口映射重新分配」。

### 不可达告警

- `[ROUTER] 内网服务不可达`
- `[NAS] 内网服务不可达`

### 防重复

同一端口 60 秒内不重复推送。

---

## Web 配置

在 **在路由器启动后执行** 中只添加一条：

```bash
/etc/storage/bin/natmap/check_ip_change.sh &
```

**不要**添加 `start_router.sh` 或 `start_nas.sh`，原因：

- 开机时 PPPoE 拨号尚未完成，start 脚本会误判内网不可达并发送错误告警
- 主脚本启动后 30 秒内拨号完成，自动拉起服务，流程正常

在 **在路由器关闭之前执行** 中添加：

```bash
/etc/storage/bin/natmap/router/stop_router.sh
/etc/storage/bin/natmap/nas/stop_nas.sh
```

---

## 手动命令

| 操作 | 命令 |
|------|------|
| 启动所有服务 | `/etc/storage/bin/natmap/check_ip_change.sh &` |
| 停止所有服务 | `stop_router.sh` + `stop_nas.sh` + kill 主进程 |
| 重启主监控 | `pkill -f check_ip_change.sh`，等待 2 秒后重新启动 |
| 查看进程 | `ps \| grep -E "natmap\|monitor\|check_ip" \| grep -v grep` |
| 查看防火墙 | `iptables -L INPUT -n \| grep ACCEPT` |
| 查看放行端口 | `cat /tmp/natmap_router_port` 和 `cat /tmp/natmap_nas_port` |
| 测试自动修复 | `iptables -D INPUT -p tcp --dport <端口> -j ACCEPT`，等 15~30 秒 |
| 查看实时日志 | `tail -f /etc/storage/bin/natmap/router/logs/router_ip_monitor.log` |
| 查看调试日志 | `tail -f /etc/storage/bin/natmap/router/logs/router_debug.log` |

---

## 日志与轮转

| 日志文件 | 记录者 | 内容 |
|----------|--------|------|
| `router_ip_monitor.log` / `nas_ip_monitor.log` | `check_ip_change.sh` | IP 变化、保活事件 |
| `router_natmap.log` / `nas_natmap.log` | `natmap` | 公网 IP + 端口 |
| `router_debug.log` / `nas_debug.log` | `monitor_xxx.sh` | 防火墙更新、推送结果 |

轮转策略：

- 触发时间：每日凌晨 4:00~4:05
- 触发条件：文件修改时间超过 7 天 **或** 文件大小超过 1MB
- 处理方式：清空文件内容（不删除文件）

---

## STUN 服务器

| 类型 | 地址 |
|------|------|
| 国内推荐 | `stun.qq.com`、`stun.l.google.com:19302` |
| 国际通用 | `turn.cloudflare.com` |
| 自建 | 部署 coturn，指定 `-s your-vps-ip` |

---

## 故障排查

### 微信没有推送

```bash
ls -la /etc/storage/script/Sh45_wx_send.sh
tail -50 /etc/storage/bin/natmap/router/logs/router_debug.log
logread | grep -E "monitor_router|monitor_nas" | tail -20
```

### 服务无法启动

```bash
tail -50 /etc/storage/bin/natmap/router/logs/router_ip_monitor.log
ps | grep -E "natmap|monitor|check_ip" | grep -v grep
ping -c 3 172.16.10.1
ping -c 3 172.16.10.99
```

### 防火墙规则未自动补充

```bash
ls -la /tmp/natmap_router_port /tmp/natmap_nas_port
ps | grep monitor_router
logread | grep "防火墙 INPUT 规则缺失" | tail -5
```

### NAS 非时段不运行

```bash
date "+%Y-%m-%d %H:%M:%S 星期%u"
tail -20 /etc/storage/bin/natmap/nas/logs/nas_ip_monitor.log | grep "允许状态"
```

---

## 扩展与自定义

### 添加更多内网服务

1. 复制 `router/` 为 `service_xxx/`
2. 修改所有脚本中的目标 IP 和端口
3. 在 `check_ip_change.sh` 中增加对应的 `ensure_xxx` 和 `restart_natmap` 调用

### 更换推送方式

修改所有脚本中调用 `/etc/storage/script/Sh45_wx_send.sh` 的部分，替换为飞书、钉钉、邮件等，保持参数格式一致。

### 调整检测间隔

- `check_ip_change.sh` 主循环 `sleep 30`
- `monitor_xxx.sh` 主循环 `sleep 15`

---

## 注意事项

1. 所有脚本必须具有可执行权限（`chmod +x`）
2. 防火墙规则保存在内存，重启后丢失，由启动脚本重新添加
3. 日志轮转策略可防止存储撑爆
4. 端口记录文件在 `/tmp`，重启后丢失，但 natmap 日志有完整历史
5. 确保内网 IP `172.16.10.1` 和 `172.16.10.99` 固定且可达
6. 微信推送脚本需提前配置好 Webhook 或 API
7. 开机启动只加 `check_ip_change.sh` 一条命令，不要加 `start_xxx.sh`
8. 若需要更改 STUN 服务器，请修改所有 `start_xxx.sh` 中的 `-s` 参数

---

## 版本信息

| 项目 | 内容 |
|------|------|
| 脚本名称 | natmap 端口映射与自动维护系统 |
| 版本 | v1.0 |
| 上线日期 | 2026-07-15 |
| 最后更新 | 2026-07-10 |
| 适用平台 | Padavan / 老毛子固件（小米/红米路由器） |
| 依赖工具 | natmap, iptables, pgrep, flock, logger, date, awk, grep, sed, cut, tr, xargs, ping, kill, ps, sleep, tee, nohup |

---

## License

MIT
