#!/bin/sh
# 这行是 shebang，指定使用 /bin/sh 作为解释器执行本脚本

# =============================================================================
# 脚本名称: stop_nas.sh
# 用途: 停止 NAS 服务的 natmap 进程和 monitor_nas.sh
#       删除该服务曾经添加过的所有 INPUT 防火墙规则
#       从 natmap 日志提取所有历史端口，逐一删除确保无残留
# 目录: /etc/storage/bin/natmap/nas/
# 依赖: iptables, pgrep, logger, tee, date, grep, awk
# =============================================================================

# 空行

# ----------------------------------------
# 步骤1：定义日志文件路径
# ----------------------------------------

# 定义 BASE_DIR 变量，值为 natmap 根目录
BASE_DIR="/etc/storage/bin/natmap"

# 定义 NAS_DIR 变量，值为 NAS 服务目录
NAS_DIR="$BASE_DIR/nas"

# 定义 NAS_LOGS 变量，值为 NAS 日志目录
NAS_LOGS="$NAS_DIR/logs"

# 创建日志目录（如果不存在）
mkdir -p "$NAS_LOGS" 2>/dev/null

# 定义 LOG_FILE 变量，值为主控日志文件路径
LOG_FILE="$NAS_LOGS/nas_ip_monitor.log"

# 定义 LOG_FILE_NATMAP 变量，值为 natmap 输出日志文件路径
LOG_FILE_NATMAP="$NAS_LOGS/nas_natmap.log"

# 定义 CHANGED 变量，值为 0
# 操作标志，有任何实际操作时置为 1
CHANGED=0

# 空行

# ----------------------------------------
# 步骤2：辅助函数：删除指定端口的所有 INPUT 规则
# ----------------------------------------

# 定义 delete_port_rules 函数
# 参数: $1 = 端口号
delete_port_rules() {
    local port="$1"
    
    # while 循环持续删除该端口的所有规则
    while iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; do
        # 删除成功，记录日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] 已删除 INPUT 规则（端口 $port）" | tee -a "$LOG_FILE"
        logger -t "stop_nas" "已删除 INPUT 规则（端口 $port）"
        CHANGED=1
    done
}
# 函数结束

# 空行

# ----------------------------------------
# 步骤3：从端口记录文件删除
# ----------------------------------------

# 定义 PORT_FILE 变量，值为端口记录文件路径
PORT_FILE="/tmp/natmap_nas_port"

# 如果端口记录文件存在
if [ -f "$PORT_FILE" ]; then
    # 读取所有端口，排序去重后逐个删除
    for port in $(cat "$PORT_FILE" | sort -u); do
        delete_port_rules "$port"
    done
    # 删除端口记录文件
    rm -f "$PORT_FILE"
fi

# 空行

# ----------------------------------------
# 步骤4：从 natmap 日志提取所有端口并删除
# ----------------------------------------

# 如果 natmap 日志文件存在
if [ -f "$LOG_FILE_NATMAP" ]; then
    # 提取第5列（本地端口）
    grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+' "$LOG_FILE_NATMAP" | \
    awk '{print $5}' | while read port; do
        [ -z "$port" ] && continue
        delete_port_rules "$port"
    done
    
    # 备选：提取第3列（公网端口，兼容旧格式）
    grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+' "$LOG_FILE_NATMAP" | \
    awk '{print $3}' | while read port; do
        [ -z "$port" ] && continue
        delete_port_rules "$port"
    done
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] 警告: natmap日志文件不存在，无法提取端口" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "警告: natmap日志文件不存在"
fi

# 空行

# ----------------------------------------
# 步骤5：停止 natmap 进程
# ----------------------------------------

NAS_PID=$(pgrep -f "natmap.*172.16.10.99")

if [ -n "$NAS_PID" ]; then
    kill $NAS_PID 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] 已停止 NAS natmap (PID: $NAS_PID)" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "已停止 NAS natmap (PID: $NAS_PID)"
    CHANGED=1
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] NAS natmap 未运行，无需停止" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "NAS natmap 未运行，无需停止"
fi

# 空行

# ----------------------------------------
# 步骤6：停止 monitor_nas.sh 进程
# ----------------------------------------

MONITOR_PID=$(pgrep -f "monitor_nas.sh")

if [ -n "$MONITOR_PID" ]; then
    kill $MONITOR_PID 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] 已停止 monitor_nas.sh (PID: $MONITOR_PID)" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "已停止 monitor_nas.sh (PID: $MONITOR_PID)"
    CHANGED=1
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] monitor_nas.sh 未运行，无需停止" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "monitor_nas.sh 未运行，无需停止"
fi

# 空行

# ----------------------------------------
# 步骤7：清理锁文件
# ----------------------------------------

rm -f /tmp/monitor_nas.lock

# 空行

# ----------------------------------------
# 步骤8：输出总结信息
# ----------------------------------------

if [ $CHANGED -eq 1 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] NAS的natmap相关进程处理完成，添加的防火墙规则已删除" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "NAS的natmap相关进程处理完成，添加的防火墙规则已删除"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_nas] NAS的natmap相关进程未运行，无需处理" | tee -a "$LOG_FILE"
    logger -t "stop_nas" "NAS的natmap相关进程未运行，无需处理"
fi

# 脚本正常结束