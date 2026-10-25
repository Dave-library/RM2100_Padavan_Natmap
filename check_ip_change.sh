#!/bin/sh
# 这行是 shebang，指定使用 /bin/sh 作为解释器执行本脚本
# /bin/sh 是 POSIX 兼容的 shell，在 Padavan 系统中指向 busybox 的 ash

# 空行，用于分隔文件头说明和实际代码

# ============================================================================
# 这一行是注释分隔线，用于视觉上划分代码块
# 脚本名称: check_ip_change.sh
# 功能: 监控 WAN IP 变化，自动重启 natmap，NAS 时段控制
# 目录: /etc/storage/bin/natmap/
# 依赖: natmap, iptables, pgrep, ping, logger, date, awk, grep, sed
# 说明: 本脚本是核心主控脚本，需常驻后台运行，开机自启
# ============================================================================
# 注释分隔线结束

# 空行，分隔文件头说明和步骤1

# ----------------------------------------
# 这一行是注释分隔线，标记步骤1的开始
# 步骤1：启动提示与变量初始化
# ----------------------------------------
# 步骤1注释结束

# echo 命令在终端输出一行文本，让用户知道脚本已经启动
# $$ 是当前 shell 的进程 ID，用于标识这个脚本实例
# 这行提示会显示在 SSH 终端中
echo "IP 变化检测脚本已启动 (PID: $$)，正在后台监控 WAN IP..."

# 空行，分隔不同命令

# date +%s 获取当前 Unix 时间戳（从 1970-01-01 00:00:00 UTC 开始的秒数）
# 把获取到的值赋给 SCRIPT_START_TIME 变量
# 这个变量用于判断脚本是否刚启动（手动重启场景）
SCRIPT_START_TIME=$(date +%s)

# export 把变量导出为环境变量
# 这样在函数内部也能访问到这个值
# 如果不 export，函数里读取不到这个变量
export SCRIPT_START_TIME

# 空行，分隔步骤1和步骤2

# ----------------------------------------
# 这一行是注释分隔线，标记步骤2的开始
# 步骤2：定义目录与日志路径
# ----------------------------------------
# 步骤2注释结束

# 定义 BASE_DIR 变量，值为所有 natmap 相关文件的根目录路径
# 这个目录存放所有脚本、日志、配置
BASE_DIR="/etc/storage/bin/natmap"

# 定义 ROUTER_DIR 变量，值为 ROUTER 服务专用目录路径
# 存放 ROUTER 的启动脚本、停止脚本、监控脚本
ROUTER_DIR="$BASE_DIR/router"

# 定义 NAS_DIR 变量，值为 NAS 服务专用目录路径
# 存放 NAS 的启动脚本、停止脚本、监控脚本
NAS_DIR="$BASE_DIR/nas"

# 定义 ROUTER_LOGS 变量，值为 ROUTER 的日志子目录路径
# 存放 ROUTER 的所有日志文件
ROUTER_LOGS="$ROUTER_DIR/logs"

# 定义 NAS_LOGS 变量，值为 NAS 的日志子目录路径
# 存放 NAS 的所有日志文件
NAS_LOGS="$NAS_DIR/logs"

# mkdir -p 创建目录，-p 表示如果上级目录不存在，也会一起创建
# "$ROUTER_LOGS" "$NAS_LOGS" 是要创建的两个目录路径
# 2>/dev/null 把错误输出（stderr）重定向到 /dev/null，丢弃提示信息
# 比如目录已存在时，mkdir 会报错，这个命令忽略这些错误
mkdir -p "$ROUTER_LOGS" "$NAS_LOGS" 2>/dev/null

# 空行，分隔目录定义和日志文件定义

# 定义 ROUTER_MAIN 变量，值为 ROUTER 主控日志文件路径
# 这个文件记录 check_ip_change.sh 对 ROUTER 服务的所有操作
ROUTER_MAIN="$ROUTER_LOGS/router_ip_monitor.log"

# 定义 ROUTER_NATMAP 变量，值为 ROUTER 的 natmap 输出日志文件路径
# natmap 程序产生的标准输出会重定向到这个文件
ROUTER_NATMAP="$ROUTER_LOGS/router_natmap.log"

# 定义 NAS_MAIN 变量，值为 NAS 主控日志文件路径
# 这个文件记录 check_ip_change.sh 对 NAS 服务的所有操作
NAS_MAIN="$NAS_LOGS/nas_ip_monitor.log"

# 定义 NAS_NATMAP 变量，值为 NAS 的 natmap 输出日志文件路径
# NAS 的 natmap 程序输出会重定向到这个文件
NAS_NATMAP="$NAS_LOGS/nas_natmap.log"

# 空行，分隔日志文件定义和启动信息记录

# date '+%Y-%m-%d %H:%M:%S' 生成当前时间，格式如 "2026-06-21 11:55:30"
# tee -a 做两件事：1) 在终端（stdout）显示 2) 追加（-a append）到文件
# 这条命令将启动信息同时输出到终端和 ROUTER_MAIN 日志文件
echo "$(date '+%Y-%m-%d %H:%M:%S') - IP 变化检测脚本已启动" | tee -a "$ROUTER_MAIN"

# 同样写入 NAS 主控日志，保持两个日志文件都有启动记录
# 这样无论查看哪个日志都能看到脚本启动时间
echo "$(date '+%Y-%m-%d %H:%M:%S') - IP 变化检测脚本已启动" | tee -a "$NAS_MAIN"

# logger 命令将信息写入系统日志（/var/log/messages 或通过 syslog）
# -t "check_ip" 指定标签（tag），方便在系统日志中过滤查找
# 系统日志可以通过 logread 命令查看
logger -t "check_ip" "IP 变化检测脚本已启动 (PID: $$)"

# 空行，分隔步骤2和步骤3

# ----------------------------------------
# 这一行是注释分隔线，标记步骤3的开始
# 步骤3：函数定义
# ----------------------------------------
# 步骤3注释结束

# 空行，分隔步骤3标题和第一个函数

# ---------- 3.1 获取当前 WAN IP ----------
# 这一行是注释分隔线，标记第3.1节开始
# 定义一个名为 get_wan_ip 的函数
# 这个函数从 ppp0 接口提取公网 IP 地址
# 函数没有参数，成功时返回 IP 字符串，失败返回空字符串
get_wan_ip() {
    # 这是函数体的开始，左花括号必须单独一行或跟在函数名后

    # ifconfig 命令显示 ppp0 网络接口的信息
    # 2>/dev/null 将错误输出（如接口不存在）重定向到 /dev/null
    # | 管道符号，将前一个命令的输出传递给下一个命令
    # grep 'inet addr' 过滤出包含 "inet addr" 的行（IP 地址行）
    # awk -F: 以冒号作为分隔符，取第2个字段
    # 第二个 awk '{print $1}' 取第1个单词（纯 IP 地址）
    # 最终输出类似 "100.64.251.187"
    ifconfig ppp0 2>/dev/null | grep 'inet addr' | awk -F: '{print $2}' | awk '{print $1}'
}
# 这是函数体的结束，右花括号单独一行

# 空行，分隔两个函数

# ---------- 3.2 不可达计数器（每日重置） ----------
# 这一行是注释分隔线，标记第3.2节开始
# 定义 get_unreach_count 函数
# 参数: $1 = 服务标识 (router 或 nas)
# 这个函数统计不可达事件的次数，每天自动重置
# 每次调用返回当前计数，并自动加1
get_unreach_count() {
    # 函数体开始

    # local 声明局部变量，仅在本函数内有效
    # 把第一个参数（$1）保存到 service 变量
    local service="$1"

    # 空行，分隔变量声明和文件路径构建

    # 构建计数器文件的完整路径
    # /etc/storage 是闪存分区，断电重启后数据不会丢失
    # 文件名格式: natmap_unreach_router.txt 或 natmap_unreach_nas.txt
    local COUNT_FILE="/etc/storage/natmap_unreach_${service}.txt"

    # date '+%Y-%m-%d' 获取当前日期，格式是 "2026-06-21"
    # 赋值给 TODAY 变量，用于和文件中保存的日期比较
    TODAY=$(date '+%Y-%m-%d')

    # 空行，分隔变量定义和逻辑判断

    # if [ ! -f "$COUNT_FILE" ] 判断计数器文件是否不存在
    # ! 是逻辑非，-f 测试文件是否存在且是普通文件
    if [ ! -f "$COUNT_FILE" ]; then
        # 文件不存在，创建新文件
        # echo "$TODAY|1" 输出 "2026-06-21|1"
        # > 覆盖写入文件
        echo "$TODAY|1" > "$COUNT_FILE"
        # echo "1" 返回数字 1 作为函数输出
        echo "1"
        # return 退出函数，不执行后面的代码
        return
    fi
    # if 语句结束

    # 空行，分隔两个 if 块

    # 读取文件中保存的日期
    # cut -d'|' -f1 以 | 作为分隔符，取第1个字段（日期部分）
    SAVED_DATE=$(cut -d'|' -f1 "$COUNT_FILE")

    # 读取文件中保存的计数
    # cut -d'|' -f2 以 | 作为分隔符，取第2个字段（计数部分）
    SAVED_COUNT=$(cut -d'|' -f2 "$COUNT_FILE")

    # 空行，分隔读取和判断

    # 如果保存的日期不是今天
    # [ "$SAVED_DATE" != "$TODAY" ] 比较两个字符串是否不相等
    if [ "$SAVED_DATE" != "$TODAY" ]; then
        # 日期不同，重置为今天和计数 1
        echo "$TODAY|1" > "$COUNT_FILE"
        # 返回 1（今天是第一次不可达）
        echo "1"
    else
        # 日期相同（今天已经有过不可达记录）
        # 计数加 1
        NEW_COUNT=$((SAVED_COUNT + 1))
        # 写入更新后的计数
        echo "$TODAY|$NEW_COUNT" > "$COUNT_FILE"
        # 返回新计数
        echo "$NEW_COUNT"
    fi
    # 内层 if 语句结束
}
# 函数结束，右花括号

# 空行，分隔两个函数

# ---------- 3.3 识别 IP 变化原因 ----------
# 这一行是注释分隔线，标记第3.3节开始
# 定义 get_change_reason 函数
# 根据系统运行状态判断本次 IP 变化的原因
# 返回一个描述字符串，用于微信推送内容
get_change_reason() {
    # 函数体开始

    # 获取系统已运行的秒数（系统启动至今的时间）
    # /proc/uptime 第1列是运行秒数（浮点数，如 12345.67）
    # awk '{print $1}' 取第1列
    # cut -d. -f1 以 . 为分隔符取整数部分（12345）
    local uptime_seconds=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)

    # 空行，分隔不同变量赋值

    # date +%H 获取当前小时（两位数，如 08、14、23）
    local current_hour=$(date +%H)

    # date +%M 获取当前分钟（两位数，如 05、30、59）
    local current_min=$(date +%M)

    # 空行，分隔获取和计算

    # 将小时和分钟转换为当天从 0 点开始的分钟数
    # 10#$current_hour 强制按十进制解释
    # 原因：如果 current_hour 是 "08"，不加 10# 会被当成八进制导致错误
    # 公式：小时 * 60 + 分钟 = 当天分钟数
    local current_time=$((10#$current_hour * 60 + 10#$current_min))

    # 系统日志文件路径，用于检查 PPPoE 断线记录
    # /tmp/syslog.log 是 Padavan 的系统日志文件
    local log_file="/tmp/syslog.log"

    # 获取脚本启动时间戳，如果 SCRIPT_START_TIME 未定义则用当前时间
    # ${SCRIPT_START_TIME:-$(date +%s)} 是参数扩展语法
    # 如果 SCRIPT_START_TIME 有值，使用它；否则执行 date +%s 获取当前时间
    local script_start_time=${SCRIPT_START_TIME:-$(date +%s)}

    # 获取当前时间戳
    local current_time_stamp=$(date +%s)

    # 计算脚本已运行多少秒
    # current_time_stamp - script_start_time = 脚本运行时长
    local script_age=$((current_time_stamp - script_start_time))

    # 空行，分隔变量定义和第一个场景判断

    # ---- 场景1：手动或定时重启 ----
    # 判断条件：脚本启动不到120秒 且 系统运行不到600秒
    # 120秒是刚启动的窗口期，600秒是系统刚重启的窗口期
    # -a 表示逻辑与（AND）
    if [ $script_age -lt 120 ] && [ $uptime_seconds -lt 600 ]; then
        # 检查是否在凌晨 3:00~3:05（180-185 分钟）
        # 180 分钟 = 3:00，185 分钟 = 3:05
        if [ $current_time -ge 180 ] && [ $current_time -le 185 ]; then
            # 在 3:00~3:05，判定为定时重启（计划任务）
            echo "定时重启（凌晨 3:00）"
        else
            # 不在这个时间段，判定为手动重启（SSH 或 Web 界面触发）
            echo "手动重启（SSH/Web 触发）"
        fi
        # 内层 if 语句结束
        # return 返回结果，不再执行后面的判断
        return
    fi
    # 外层 if 语句结束

    # 空行，分隔场景1和备用场景

    # ---- 场景1备用：仅依赖系统运行时间 ----
    # 如果系统运行不到 600 秒（10分钟），也可能是刚重启
    # 这个判断不依赖脚本启动时间，更准确
    if [ $uptime_seconds -lt 600 ]; then
        if [ $current_time -ge 180 ] && [ $current_time -le 185 ]; then
            echo "定时重启（凌晨 3:00）"
        else
            echo "手动重启（SSH/Web 触发）"
        fi
        # 内层 if 语句结束
        return
    fi
    # 外层 if 语句结束

    # 空行，分隔场景1和场景2

    # ---- 场景2：PPPoE 断线重连 ----
    # 检查系统日志中是否有 PPPoE 断线记录
    # -f 测试文件是否存在
    if [ -f "$log_file" ]; then
        # 搜索 pppd 相关行，过滤 LCP down 或 disconnected
        # grep "pppd" 匹配包含 pppd 的行
        # grep -E "LCP down|disconnected" 使用扩展正则匹配断线关键词
        # tail -1 取匹配结果的最后一条（最近的）
        # awk '{print $1" "$2}' 取第1和第2列（日期和时间）
        # date -d "- 60 seconds" 判断该时间是否在 60 秒内
        # 2>/dev/null 丢弃 date 命令的错误输出
        local pppd_down=$(grep "pppd" "$log_file" | grep -E "LCP down|disconnected" | tail -1 | awk '{print $1" "$2}' | date -d "- 60 seconds" 2>/dev/null)
        # if [ -n "$pppd_down" ] 如果 pppd_down 非空
        # 说明 60 秒内有断线记录
        if [ -n "$pppd_down" ]; then
            echo "网络断线重连（PPPoE 链路中断）"
            return
        fi
        # 内层 if 语句结束
    fi
    # 外层 if 语句结束

    # 空行，分隔场景2和场景3

    # ---- 场景3：运营商维护 ----
    # 判断是否在凌晨 2:00~5:00（120-300 分钟）
    # 运营商通常在这个时段进行网络维护，导致 IP 变化
    if [ $current_time -ge 120 ] && [ $current_time -le 300 ]; then
        echo "运营商例行维护（凌晨时段重拨）"
        return
    fi
    # if 语句结束

    # 空行，分隔场景3和场景4

    # ---- 场景4：其他（兜底） ----
    # 如果以上所有场景都不匹配，使用这个默认描述
    echo "外网链路变化，重新拨号"
}
# 函数结束

# 空行，分隔两个函数

# ---------- 3.4 NAS 时段判断 ----------
# 这一行是注释分隔线，标记第3.4节开始
# 判断 NAS 是否在允许的时间段内
# 允许时段：周五 18:00 到 周日 24:00
# 返回值: 0=允许（true），1=不允许（false）
# 返回值 0 在 shell 中表示成功/真
is_nas_allowed() {
    # 函数体开始

    # date +%u 获取星期几
    # %u 返回 1-7，其中 1=周一，7=周日
    local weekday=$(date +%u)

    # 空行，分隔变量定义

    # date +%H 获取当前小时 (0-23)
    local hour=$(date +%H)

    # date +%M 获取当前分钟 (0-59)
    local min=$(date +%M)

    # 空行，分隔获取和计算

    # 当前距 0 点的分钟数，10#$ 强制十进制
    local current=$((10#$hour * 60 + 10#$min))

    # 空行，分隔计算和判断

    # 判断是否满足允许条件
    # 第1个条件：周五（weekday == 5）且当前分钟 >= 1080（18:00）
    if [ "$weekday" -eq 5 ] && [ $current -ge 1080 ]; then
        # 周五 18:00 之后允许运行
        # return 0 表示允许
        return 0
    # elif 是 else-if，第2个条件：周六（weekday == 6）
    elif [ "$weekday" -eq 6 ]; then
        # 周六全天允许运行（0:00-24:00）
        return 0
    # 第3个条件：周日（weekday == 7）且当前分钟 <= 1440（24:00）
    elif [ "$weekday" -eq 7 ] && [ $current -le 1440 ]; then
        # 周日 24:00 之前允许运行
        return 0
    else
        # 其他时间（周一到周四，周五18:00之前，周日24:00之后）不允许
        return 1
    fi
    # if 语句结束
}
# 函数结束

# 空行，分隔两个函数

# ---------- 3.5 日志轮转（每天 4:00~6:00 执行） ----------
# 这一行是注释分隔线，标记第3.5节开始
# 检查日志文件是否超过7天或大于1MB
# 满足任一条件则清空文件内容
# ★★★ 修改：时间窗口从 4:00-4:05 改为 4:00-6:00（2小时窗口，不容易错过）
# ★★★ 修改：增加标志文件机制，防止同一天重复执行
rotate_logs() {
    # 函数体开始

    # 检查今天是否已经执行过轮转
    # 标志文件存放在 /tmp 目录，格式：natmap_log_rotate_done_YYYYMMDD
    # /tmp 重启后清空，所以每天都会重新计数
    local flag_file="/tmp/natmap_log_rotate_done_$(date '+%Y%m%d')"

    # 如果标志文件存在，说明今天已经执行过轮转，直接返回
    if [ -f "$flag_file" ]; then
        return
    fi
    # if 语句结束

    # 空行，分隔标志检查和时间检查

    # date +%H 获取当前小时
    local hour=$(date +%H)

    # 判断当前小时是否在 4:00-6:00 之间
    # 4:00-6:00 有 2 小时窗口，不容易错过
    # [ $hour -lt 4 ] 小于4点（0-3点）不执行
    # [ $hour -ge 6 ] 大于等于6点（6-23点）不执行
    # 只有 4 点和 5 点才执行
    if [ $hour -lt 4 ] || [ $hour -ge 6 ]; then
        # 不在 4:00-6:00 之间，直接返回
        # 注意：不创建标志文件，允许后续再尝试
        return
    fi
    # if 语句结束

    # ---- 执行日志清理 ----
    # 创建标志文件，防止同一天重复执行
    touch "$flag_file"

    # 空行，分隔标志创建和日志处理

    # ---- 处理 ROUTER 日志 ----
    # for 循环遍历 ROUTER 的两个日志文件
    # in "$ROUTER_MAIN" "$ROUTER_NATMAP" 指定要遍历的变量列表
    for log in "$ROUTER_MAIN" "$ROUTER_NATMAP"; do
        # 循环体开始

        # 检查文件是否存在
        if [ -f "$log" ]; then
            # find -mtime +7 检查文件修改时间是否超过 7 天
            # -mtime +7 表示修改时间在 7 天之前的文件
            # 2>/dev/null 丢弃 find 的错误输出
            # grep -q . 静默检查是否有输出（-q 安静模式，. 匹配任意字符）
            if find "$log" -mtime +7 2>/dev/null | grep -q .; then
                # 超过 7 天，清空文件
                # > "$log" 将空输出重定向到文件，覆盖原内容
                > "$log"
                # 记录操作到主控日志
                # >> 追加到文件
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 日志轮转：已清空 $log（超过7天）" >> "$ROUTER_MAIN"
                # logger 记录到系统日志
                logger -t "check_ip" "日志轮转：已清空 $log（超过7天）"
            # elif 检查文件大小是否大于 1MB
            # stat -c %s 获取文件大小（字节数）
            # 1048576 = 1 * 1024 * 1024，即 1MB
            elif [ $(stat -c %s "$log" 2>/dev/null) -gt 1048576 ]; then
                # 大于 1MB，清空文件
                > "$log"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 日志轮转：已清空 $log（大于1MB）" >> "$ROUTER_MAIN"
                logger -t "check_ip" "日志轮转：已清空 $log（大于1MB）"
            fi
            # 内层 if 结束
        fi
        # 外层 if 结束
    done
    # for 循环结束

    # 空行，分隔 ROUTER 和 NAS 处理

    # ---- 处理 NAS 日志 ----
    # for 循环遍历 NAS 的两个日志文件
    for log in "$NAS_MAIN" "$NAS_NATMAP"; do
        # 循环体开始
        if [ -f "$log" ]; then
            if find "$log" -mtime +7 2>/dev/null | grep -q .; then
                > "$log"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 日志轮转：已清空 $log（超过7天）" >> "$NAS_MAIN"
                logger -t "check_ip" "日志轮转：已清空 $log（超过7天）"
            elif [ $(stat -c %s "$log" 2>/dev/null) -gt 1048576 ]; then
                > "$log"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 日志轮转：已清空 $log（大于1MB）" >> "$NAS_MAIN"
                logger -t "check_ip" "日志轮转：已清空 $log（大于1MB）"
            fi
        fi
    done
    # for 循环结束
}
# 函数结束

# 空行，分隔两个函数

# ---------- 3.6 确保 ROUTER 服务运行（直接启动） ----------
# 这一行是注释分隔线，标记第3.6节开始
# 确保 ROUTER 服务运行，进程不存在时立即尝试恢复
# 【关键修复】开头增加冷却检查，6小时内不重复检测
ensure_router() {
    # 函数体开始

    # date +%s 获取当前时间戳（秒）
    local current_time=$(date +%s)

    # 空行，分隔变量定义和冷却检查

    # ★★★ 冷却检查 ★★★
    # 如果当前时间小于下次允许检测的时间，说明还在冷却期内
    # next_ping_router 是外部变量，在函数外定义（步骤4）
    if [ $current_time -lt $next_ping_router ]; then
        # 计算剩余冷却时间（分钟）
        # $(( )) 是算术扩展，进行数学运算
        # ($next_ping_router - $current_time) / 60 将秒转换为分钟
        local remain_min=$(( ($next_ping_router - $current_time) / 60 ))
        # 记录跳过检测到日志，方便排查问题
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_router] 冷却中，跳过检测 (剩余 ${remain_min} 分钟)" >> "$ROUTER_MAIN"
        # return 退出函数，不执行后续代码
        return
    fi
    # if 语句结束

    # 空行，分隔冷却检查和函数主体

    # 记录函数被调用，写入 ROUTER 主控日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_router] 被调用" >> "$ROUTER_MAIN"

    # 空行，分隔日志记录和进程检查

    # 检查 ROUTER 的 natmap 进程是否存在
    # pgrep -f 匹配完整命令行（不限于进程名）
    # 匹配模式 "natmap.*172.16.10.1.*5001" 是正则表达式
    # .* 匹配任意字符，确保匹配完整的 natmap 命令行
    # > /dev/null 将标准输出重定向到 /dev/null（丢弃）
    # ! 取反，表示"如果不存在"
    if ! pgrep -f "natmap.*172.16.10.1.*5001" > /dev/null; then
        # 进程不存在，尝试 ping 目标 IP
        # -c 1 只发一个 ICMP 包，-W 2 超时 2 秒
        # > /dev/null 2>&1 将标准输出和标准错误都重定向到 /dev/null
        if ping -c 1 -W 2 172.16.10.1 > /dev/null 2>&1; then
            # 可达，清除冷却并启动
            # next_ping_router 是外部变量，0 表示无冷却
            next_ping_router=0

            # 构建日志消息
            local msg="ROUTER IP 可达，启动 router natmap 和 monitor"
            # tee -a 同时输出到终端和追加到日志文件
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$ROUTER_MAIN"
            # logger 写入系统日志
            logger -t "check_ip" "$msg"

            # 空行，分隔日志和启动命令

            # 直接启动 natmap（后台运行）
            # 完整路径: /etc/storage/bin/natmap/natmap
            # -d 守护进程模式（后台运行）
            # -s turn.cloudflare.com 指定 STUN 服务器
            # -h baidu.com 指定心跳检测域名
            # -b 0 绑定所有网络接口
            # -t 172.16.10.1 目标内网 IP
            # -p 5001 目标端口
            # 2>&1 把标准错误重定向到标准输出
            # | while read line 逐行读取输出并添加时间戳
            # >> "$ROUTER_NATMAP" 追加到 ROUTER 的 natmap 日志文件
            # & 放在后台运行，不阻塞当前脚本
            /etc/storage/bin/natmap/natmap -d -s turn.cloudflare.com -h baidu.com -b 0 -t 172.16.10.1 -p 5001 2>&1 | while read line; do
                # 循环体：在每一行输出前加上当前时间戳
                echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
            done >> "$ROUTER_NATMAP" &

            # 空行，分隔启动和等待

            # sleep 5 让 natmap 有足够时间创建日志文件和初始化
            sleep 5

            # 空行，分隔等待和监控启动

            # 检查 monitor_router.sh 是否已运行
            if ! pgrep -f "monitor_router.sh" > /dev/null; then
                # 启动 monitor_router.sh
                # > "$ROUTER_LOGS/router_debug.log" 2>&1 重定向所有输出到 debug 日志
                /etc/storage/bin/natmap/router/monitor_router.sh > "$ROUTER_LOGS/router_debug.log" 2>&1 &
                # 记录启动信息到主控日志
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 已启动 monitor_router.sh" >> "$ROUTER_MAIN"
            fi
            # 内层 if 结束
        else
            # 不可达，设置 6 小时冷却
            # COOLDOWN_SECONDS 是外部变量（步骤4），值为 21600 秒
            next_ping_router=$((current_time + COOLDOWN_SECONDS))

            # 空行，分隔计算和日志

            # date -d "@$next_ping_router" 将时间戳转换为可读格式
            # @ 表示后面跟的是 Unix 时间戳
            next_time_str=$(date -d "@$next_ping_router" '+%Y-%m-%d %H:%M:%S')

            # 构建日志消息
            local msg="ROUTER IP 不可达，下次检测: $next_time_str"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$ROUTER_MAIN"
            logger -t "check_ip" "$msg"

            # 空行，分隔日志和推送

            # 获取不可达计数器
            # 调用 get_unreach_count 函数，传入参数 "router"
            local COUNT=$(get_unreach_count "router")

            # 组装微信推送标题
            local title="[ROUTER] 端口更新失败 (第${COUNT}条)"
            # 组装微信推送内容
            # 注意：这里使用真实的换行符，不是 \n 字符串
            local content="原因: 目标 IP 172.16.10.1 无法 ping 通
本地地址: 172.16.10.1:5001
下次检测: ${next_time_str} (约 6 小时后)"

            # 空行，分隔内容组装和发送

            # 调用微信发送脚本
            # 脚本路径: /etc/storage/script/Sh45_wx_send.sh
            # 参数: send_message 子命令，标题，内容
            /etc/storage/script/Sh45_wx_send.sh send_message "$title" "$content"
        fi
        # 外层 if 结束
    else
        # 进程存在，清除冷却
        # 将 next_ping_router 设为 0，表示无冷却
        next_ping_router=0

        # 空行，分隔清除和记录

        # 记录进程存在到日志（用于调试）
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_router] ROUTER 进程存在" >> "$ROUTER_MAIN"
    fi
    # if 结束
}
# 函数结束

# 空行，分隔两个函数

# ---------- 3.7 确保 NAS 服务运行（直接启动） ----------
# 这一行是注释分隔线，标记第3.7节开始
# 确保 NAS 服务运行，进程不存在时立即尝试恢复
# 【关键修复】开头增加冷却检查，6小时内不重复检测
# 进程存在时也定期检查连通性，网络不通时发送告警
ensure_nas() {
    # 函数体开始

    # date +%s 获取当前时间戳（秒）
    local current_time=$(date +%s)

    # 空行，分隔变量定义和冷却检查

    # ★★★ 冷却检查 ★★★
    # 如果当前时间小于下次允许检测的时间，说明还在冷却期内
    # next_ping_nas 是外部变量，在函数外定义（步骤4）
    if [ $current_time -lt $next_ping_nas ]; then
        # 计算剩余冷却时间（分钟）
        local remain_min=$(( ($next_ping_nas - $current_time) / 60 ))
        # 记录跳过检测到日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_nas] 冷却中，跳过检测 (剩余 ${remain_min} 分钟)" >> "$NAS_MAIN"
        # 返回，不执行后续代码
        return
    fi
    # if 语句结束

    # 空行，分隔冷却检查和函数主体

    # 记录函数被调用，写入 NAS 主控日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_nas] 被调用" >> "$NAS_MAIN"

    # 空行，分隔日志记录和时段判断

    # ---- 第1步：判断是否在允许时段 ----
    # 调用 is_nas_allowed 函数，返回值 0 表示允许，1 表示不允许
    # 初始化 current_allowed 变量为 0（不允许）
    local current_allowed=0
    if is_nas_allowed; then
        # 在允许时段，设置状态为 1
        current_allowed=1
    else
        # 不在允许时段，保持为 0
        current_allowed=0
    fi
    # if 语句结束

    # 空行，分隔判断和日志

    # 记录时段状态到日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_nas] NAS 允许状态: $current_allowed" >> "$NAS_MAIN"

    # 空行，分隔日志和状态变化处理

    # ---- 第2步：状态变化时记录日志 ----
    # last_nas_allowed_state 是外部变量，初始值为 -1
    # -ne 表示不等于（not equal）
    if [ $last_nas_allowed_state -ne $current_allowed ]; then
        # 状态发生了变化，记录具体的变化信息
        if [ $current_allowed -eq 1 ]; then
            # 进入允许时段
            local msg="NAS 的 natmap 进程已进入允许时段 (周五18:00-周日24:00)"
        else
            # 离开允许时段，显示具体原因
            local weekday=$(date +%u)
            local hour=$(date +%H)
            local min=$(date +%M)
            local current_minutes=$((10#$hour * 60 + 10#$min))

            # 空行，分隔变量定义和条件判断

            # 判断离开允许时段的具体原因
            # 第1个条件：周五且未到18:00
            if [ $weekday -eq 5 ] && [ $current_minutes -lt 1080 ]; then
                msg="NAS 的 natmap 进程未到启动时间段（周五18:00-周日24:00）"
            # 第2个条件：周日且已过24:00（即下周一0点）
            elif [ $weekday -eq 7 ] && [ $current_minutes -gt 1440 ]; then
                msg="NAS 的 natmap 进程已过运行时段 (周日24:00结束)"
            # 第3个条件：周一到周四（工作日）
            elif [ $weekday -eq 1 ] || [ $weekday -eq 2 ] || [ $weekday -eq 3 ] || [ $weekday -eq 4 ]; then
                msg="NAS 的 natmap 进程仅允许周五18:00至周日24:00运行，当前不在该时段"
            else
                # 其他情况（边界条件）
                msg="NAS 的 natmap 进程不在允许时段"
            fi
        fi
        # 内层 if 结束

        # 空行，分隔消息构建和日志记录

        # 记录状态变化到日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$NAS_MAIN"
        logger -t "check_ip" "$msg"

        # 更新状态记录变量
        last_nas_allowed_state=$current_allowed
    fi
    # 外层 if 结束

    # 空行，分隔状态变化处理和强制停止

    # ---- 第3步：非允许时段：强制停止 ----
    if [ $current_allowed -eq 0 ]; then
        # 当前不在允许时段，检查 NAS 进程是否存在
        if pgrep -f "natmap.*172.16.10.99.*5001" > /dev/null; then
            # 进程存在，需要强制停止
            local msg="不在允许时段，强制停止 NAS 的 natmap 进程"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$NAS_MAIN"
            logger -t "check_ip" "$msg"

            # 空行，分隔日志和停止命令

            # 获取所有匹配的 PID 并逐个杀死
            # for pid in $(命令) 循环遍历命令输出的每一行
            for pid in $(pgrep -f "natmap.*172.16.10.99.*5001"); do
                # kill 发送 TERM 信号终止进程
                # 2>/dev/null 忽略错误（进程可能已经不存在）
                kill $pid 2>/dev/null
            done
            # for 循环结束

            # 同时停止 monitor_nas.sh 进程
            # pkill 按进程名杀死进程
            pkill -f "monitor_nas.sh" 2>/dev/null
        fi
        # 内层 if 结束

        # 清除 NAS 冷却标志
        next_ping_nas=0
        # 返回，不执行后续代码
        return
    fi
    # 外层 if 结束

    # 空行，分隔强制停止和进程检查

    # ---- 第4步：允许时段：检查进程 ----
    if pgrep -f "natmap.*172.16.10.99.*5001" > /dev/null; then
        # 进程存在，清除冷却标志
        next_ping_nas=0

        # 空行，分隔清除和日志

        # 记录进程存在
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_nas] NAS 进程存在" >> "$NAS_MAIN"

        # 空行，分隔日志和连通性检查

        # ★★★ 新增功能：进程存在时也定期检查网络连通性 ★★★
        # 每 180 秒（3 分钟）主动 ping 一次目标 IP
        # 原因：进程可能存活但网络不通（如网线断开），此时不会触发不可达推送

        # 读取上次 ping 检查的时间戳
        # 如果文件不存在则默认为 0
        # cat 读取文件内容，2>/dev/null 丢弃错误
        # || echo 0 如果 cat 失败，输出 0
        local last_ping_check=$(cat /tmp/nas_last_ping_check 2>/dev/null || echo 0)

        # 空行，分隔读取和计算

        # 计算距离上次检查过去了多少秒
        local time_since_last_check=$((current_time - last_ping_check))

        # 空行，分隔计算和检查

        # 如果距离上次检查超过 180 秒，执行一次检查
        if [ $time_since_last_check -ge 180 ]; then
            # 将当前时间写入检查记录文件，用于下次判断
            echo $current_time > /tmp/nas_last_ping_check

            # 空行，分隔写入和 ping

            # 执行 ping 测试，检测 NAS 是否可达
            if ! ping -c 1 -W 2 172.16.10.99 > /dev/null 2>&1; then
                # ---- NAS 不可达：发送微信告警 ----
                # 计算下次检测时间：6 小时后（21600 秒）
                local next_check_time=$((current_time + 21600))
                # 将时间戳转换为可读格式
                local next_check_str=$(date -d "@$next_check_time" '+%Y-%m-%d %H:%M:%S')

                # 空行，分隔计算和推送

                # 获取不可达计数器（每日重置）
                local COUNT=$(get_unreach_count "nas")

                # 组装微信推送内容
                local title="[NAS] 端口更新失败 (第${COUNT}条)"
                local content="原因: 目标 IP 172.16.10.99 无法 ping 通
本地地址: 172.16.10.99:5001
状态: 进程存活但网络不可达
下次检测: ${next_check_str} (约 6 小时后)"

                # 空行，分隔组装和发送

                # 调用微信发送脚本
                /etc/storage/script/Sh45_wx_send.sh send_message "$title" "$content"

                # 记录告警到系统日志
                logger -t "check_ip" "NAS 进程存活但网络不可达，已发送告警"

                # 记录到 NAS 主控日志
                echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_nas] NAS 进程存活但网络不可达，已发送告警" >> "$NAS_MAIN"

                # ★★★ 设置 6 小时冷却 ★★★
                next_ping_nas=$((current_time + 21600))
            fi
            # 内层 if 结束
        fi
        # 外层 if 结束

        # 返回，不执行后续的启动逻辑
        return
    fi
    # 外层 if 结束

    # 空行，分隔进程检查和启动逻辑

    # ---- 第5步：进程不存在，尝试启动 ----
    # 记录进程不存在（正常情况下的保活流程）
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ensure_nas] NAS 进程不存在，尝试 ping" >> "$NAS_MAIN"

    # 空行，分隔日志和 ping

    # ping 目标 IP，测试 NAS 是否可达
    if ping -c 1 -W 2 172.16.10.99 > /dev/null 2>&1; then
        # ---- 可达：清除冷却并启动服务 ----
        next_ping_nas=0

        # 构建日志消息
        local msg="NAS IP 可达，启动 nas natmap 和 monitor"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$NAS_MAIN"
        logger -t "check_ip" "$msg"

        # 空行，分隔日志和启动

        # 启动 natmap
        /etc/storage/bin/natmap/natmap -d -s turn.cloudflare.com -h baidu.com -b 0 -t 172.16.10.99 -p 5001 2>&1 | while read line; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
        done >> "$NAS_NATMAP" &

        # 空行，分隔启动和等待

        # 等待 5 秒让 natmap 创建日志文件
        sleep 5

        # 空行，分隔等待和监控启动

        # 启动 monitor_nas.sh
        if ! pgrep -f "monitor_nas.sh" > /dev/null; then
            /etc/storage/bin/natmap/nas/monitor_nas.sh > "$NAS_LOGS/nas_debug.log" 2>&1 &
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 已启动 monitor_nas.sh" >> "$NAS_MAIN"
        fi
        # 内层 if 结束
    else
        # ---- 不可达：设置 6 小时冷却并发送告警 ----
        next_ping_nas=$((current_time + COOLDOWN_SECONDS))

        # 空行，分隔计算和格式化

        # 计算下次检测时间
        local next_check_time=$((current_time + 21600))
        local next_check_str=$(date -d "@$next_check_time" '+%Y-%m-%d %H:%M:%S')

        # 空行，分隔格式化和日志

        local msg="NAS IP 不可达，下次检测: $next_check_str"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$NAS_MAIN"
        logger -t "check_ip" "$msg"

        # 空行，分隔日志和推送

        # 获取不可达计数器
        local COUNT=$(get_unreach_count "nas")

        # 发送微信通知
        local title="[NAS] 端口更新失败 (第${COUNT}条)"
        local content="原因: 目标 IP 172.16.10.99 无法 ping 通
本地地址: 172.16.10.99:5001
下次检测: ${next_check_str} (约 6 小时后)"
        /etc/storage/script/Sh45_wx_send.sh send_message "$title" "$content"
    fi
    # 外层 if 结束
}
# 函数结束

# 空行，分隔两个函数

# ---------- 3.8 IP 变化时重启 natmap ----------
# 这一行是注释分隔线，标记第3.8节开始
# IP 变化时重启 natmap，并将原因写入临时文件供 monitor 读取
# ★★★ 目标 IP 不可达时也发送微信推送 ★★★
restart_natmap() {
    # 函数体开始

    # 目标 IP 参数（从调用者传入）
    local target_ip="$1"

    # 空行，分隔参数获取和变量声明

    # 日志文件变量
    local log_file=""
    local main_log=""
    local service_name=""   # "router" 或 "nas"

    # 空行，分隔变量声明和选择

    # 根据目标 IP 选择对应的日志文件和服务名
    if [ "$target_ip" = "172.16.10.1" ]; then
        # ROUTER 服务
        log_file="$ROUTER_NATMAP"
        main_log="$ROUTER_MAIN"
        service_name="router"
    else
        # NAS 服务（目标 IP 为 172.16.10.99）
        log_file="$NAS_NATMAP"
        main_log="$NAS_MAIN"
        service_name="nas"
    fi
    # if 语句结束

    # 空行，分隔选择和变化原因获取

    # 获取变化原因（调用 get_change_reason 函数）
    local reason=$(get_change_reason)
    local msg="IP变化原因: $reason"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$main_log"
    logger -t "check_ip" "$msg"

    # 空行，分隔日志和写入原因文件

    # 写入临时文件供 monitor 脚本读取（用于推送内容）
    if [ "$target_ip" = "172.16.10.1" ]; then
        echo "$reason" > /tmp/ip_change_reason_router
    else
        echo "$reason" > /tmp/ip_change_reason_nas
    fi
    # if 语句结束

    # 空行，分隔写入和可达性检查

    # ---- 检查目标 IP 是否可达 ----
    # 发送一个 ICMP 包，超时 2 秒，丢弃所有输出
    if ! ping -c 1 -W 2 "$target_ip" > /dev/null 2>&1; then
        # ---- 目标 IP 不可达：记录日志并发送推送 ----
        local msg="目标 $target_ip 不可达，放弃重启 $service_name natmap"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$main_log"
        logger -t "check_ip" "$msg"

        # 空行，分隔日志和推送

        # ★★★ 不可达时发送微信推送 ★★★
        # 获取当前时间戳
        local current_time=$(date +%s)
        # 计算下次检测时间：6 小时后（21600 秒）
        local next_check_time=$((current_time + 21600))
        # 将时间戳转换为可读格式
        local next_check_str=$(date -d "@$next_check_time" '+%Y-%m-%d %H:%M:%S')
        # 获取不可达计数器（每日重置）
        local COUNT=$(get_unreach_count "$service_name")

        # 空行，分隔计算和推送内容

        # ${service_name^^} 将服务名转换为大写（ROUTER 或 NAS）
        local title="[${service_name^^}] 端口更新失败 (第${COUNT}条)"
        local content="原因: 目标 IP ${target_ip} 无法 ping 通
本地地址: ${target_ip}:5001
下次检测: ${next_check_str} (约 6 小时后)"

        # 调用微信发送脚本
        /etc/storage/script/Sh45_wx_send.sh send_message "$title" "$content"

        # 返回，不执行后续的重启逻辑
        return
    fi
    # if 语句结束

    # 空行，分隔可达性检查和重启逻辑

    # ---- 目标 IP 可达：执行重启 ----
    # 杀死旧进程
    local msg="IP变化，重启 $service_name natmap ($target_ip)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$main_log"
    logger -t "check_ip" "$msg"

    # 空行，分隔日志和杀死进程

    # 获取所有匹配的 PID
    for pid in $(pgrep -f "natmap.*$target_ip.*5001"); do
        kill $pid 2>/dev/null
        local kill_msg="停止旧 $service_name natmap 进程 PID=$pid"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $kill_msg" | tee -a "$main_log"
        logger -t "check_ip" "$kill_msg"
    done
    # for 循环结束

    # 空行，分隔杀死和等待

    # 等待 1 秒确保进程完全退出
    sleep 1

    # 空行，分隔等待和启动

    # 启动新进程
    # 2>&1 把错误输出也重定向到标准输出
    # while read line 逐行读取并添加时间戳
    /etc/storage/bin/natmap/natmap -d -s turn.cloudflare.com -h baidu.com -b 0 -t "$target_ip" -p 5001 2>&1 | while read line; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
    done >> "$log_file" &

    # 空行，分隔启动和日志

    local start_msg="已启动新 $service_name natmap ($target_ip)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $start_msg" | tee -a "$main_log"
    logger -t "check_ip" "$start_msg"
}
# 函数结束

# 空行，分隔两个函数

# ---------- 3.9 获取稳定 WAN IP ----------
# 这一行是注释分隔线，标记第3.9节开始
# 连续两次获取 WAN IP，相同才确认，避免临时波动
get_stable_wan_ip() {
    # 函数体开始

    # 第一次获取 WAN IP
    local ip1=$(get_wan_ip)

    # 空行，分隔获取和检查

    # [ -z "$ip1" ] 判断 ip1 是否为空字符串
    # && return 1 如果为空，返回 1（失败）
    [ -z "$ip1" ] && return 1

    # 空行，分隔检查和等待

    # 等待 5 秒让网络稳定
    sleep 5

    # 空行，分隔等待和第二次获取

    # 第二次获取 WAN IP
    local ip2=$(get_wan_ip)

    # 空行，分隔获取和比较

    # 两次相同则输出，否则返回 1（失败）
    if [ "$ip1" = "$ip2" ]; then
        echo "$ip1"
        return 0
    else
        return 1
    fi
    # if 语句结束
}
# 函数结束

# 空行，分隔步骤3和步骤4

# ----------------------------------------
# 这一行是注释分隔线，标记步骤4的开始
# 步骤4：冷却与状态变量
# ----------------------------------------
# 步骤4注释结束

# 定义 COOLDOWN_SECONDS 变量，值为 21600 秒（6小时）
# 不可达后进入冷却期，避免频繁重试
COOLDOWN_SECONDS=21600

# 定义 next_ping_router 变量，值为 0
# 表示下次允许 ping ROUTER 的时间戳，0 表示无冷却
next_ping_router=0

# 定义 next_ping_nas 变量，值为 0
# 表示下次允许 ping NAS 的时间戳，0 表示无冷却
next_ping_nas=0

# 定义 last_nas_allowed_state 变量，值为 -1
# NAS 时段状态记录，-1:初始状态，0:不允许，1:允许
last_nas_allowed_state=-1

# 空行，分隔步骤4和步骤5

# ----------------------------------------
# 这一行是注释分隔线，标记步骤5的开始
# 步骤5：主循环（永久运行）
# ----------------------------------------
# 步骤5注释结束

# 定义 last_ip_router 变量，值为空字符串
# 用于记录上次的 ROUTER IP，检测是否变化
last_ip_router=""

# 定义 last_ip_nas 变量，值为空字符串
# 用于记录上次的 NAS IP，检测是否变化
last_ip_nas=""

# 空行，分隔变量定义和主循环

# while true 创建无限循环，脚本会一直运行
# true 是 shell 内置命令，总是返回 0（成功）
while true; do
    # 循环体开始

    # 执行保活检测
    # 调用 ensure_router 函数，确保 ROUTER 服务运行
    ensure_router
    # 调用 ensure_nas 函数，确保 NAS 服务运行
    ensure_nas

    # 空行，分隔保活检测和日志轮转

    # 每日执行一次日志轮转
    # ★★★ 修改：直接调用 rotate_logs，由函数内部控制执行频率
    # 不再使用 last_rotate_date 控制，改为标志文件控制
    rotate_logs

    # 空行，分隔日志轮转和 IP 获取

    # 获取稳定 WAN IP
    # 调用 get_stable_wan_ip 函数
    stable_ip=$(get_stable_wan_ip)
    # 如果获取失败（返回空字符串）
    if [ -z "$stable_ip" ]; then
        # 等待 30 秒后继续下一轮循环
        sleep 30
        # continue 跳过本次循环剩余代码，进入下一轮
        continue
    fi
    # if 语句结束

    # 空行，分隔 IP 获取和服务处理

    # ---- 处理 ROUTER ----
    # 检查 ROUTER 进程是否存在
    if pgrep -f "natmap.*172.16.10.1.*5001" > /dev/null; then
        # 进程存在，检查 IP 是否变化
        if [ "$stable_ip" != "$last_ip_router" ]; then
            # IP 变化，调用 restart_natmap 重启 ROUTER 的 natmap
            restart_natmap "172.16.10.1"
            # 更新记录，保存当前 IP
            last_ip_router="$stable_ip"
        fi
        # 内层 if 结束
    else
        # 进程不存在，清空记录
        # 下次循环如果进程恢复，会触发 IP 变化重启
        last_ip_router=""
    fi
    # 外层 if 结束

    # 空行，分隔 ROUTER 和 NAS 处理

    # ---- 处理 NAS ----
    # 检查 NAS 进程是否存在且处于允许时段
    # && 是逻辑与，两个条件都满足才执行后面的代码
    if pgrep -f "natmap.*172.16.10.99.*5001" > /dev/null && is_nas_allowed; then
        # 进程存在且在允许时段，检查 IP 是否变化
        if [ "$stable_ip" != "$last_ip_nas" ]; then
            # IP 变化，调用 restart_natmap 重启 NAS 的 natmap
            restart_natmap "172.16.10.99"
            # 更新记录，保存当前 IP
            last_ip_nas="$stable_ip"
        fi
        # 内层 if 结束
    else
        # 进程不存在或不在允许时段，清空记录
        last_ip_nas=""
    fi
    # 外层 if 结束

    # 空行，分隔处理完成和等待

    # 等待 30 秒再进入下一轮循环
    sleep 30
done
# while 循环结束

# 脚本结束
# 这一行是文件末尾，没有实际代码