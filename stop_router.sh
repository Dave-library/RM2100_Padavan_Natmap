#!/bin/sh
# 这行是 shebang，指定使用 /bin/sh 作为解释器执行本脚本

# =============================================================================
# 脚本名称: stop_router.sh
# 用途: 停止 ROUTER 服务的 natmap 进程和 monitor_router.sh
#       删除该服务曾经添加过的所有 INPUT 防火墙规则
#       从 natmap 日志提取所有历史端口，逐一删除确保无残留
# 目录: /etc/storage/bin/natmap/router/
# 依赖: iptables, pgrep, logger, tee, date, grep, awk
# =============================================================================

# 空行

# ----------------------------------------
# 步骤1：定义日志文件路径
# ----------------------------------------

# 定义 BASE_DIR 变量，值为 natmap 根目录
BASE_DIR="/etc/storage/bin/natmap"

# 定义 ROUTER_DIR 变量，值为 ROUTER 服务目录
ROUTER_DIR="$BASE_DIR/router"

# 定义 ROUTER_LOGS 变量，值为 ROUTER 日志目录
ROUTER_LOGS="$ROUTER_DIR/logs"

# 创建日志目录（如果不存在）
mkdir -p "$ROUTER_LOGS" 2>/dev/null

# 定义 LOG_FILE 变量，值为主控日志文件路径
LOG_FILE="$ROUTER_LOGS/router_ip_monitor.log"

# 定义 LOG_FILE_NATMAP 变量，值为 natmap 输出日志文件路径
LOG_FILE_NATMAP="$ROUTER_LOGS/router_natmap.log"

# 定义 CHANGED 变量，值为 0
# 操作标志，有任何实际操作时置为 1
# 用于最后判断是否执行了有效操作（是否有规则被删除或进程被停止）
CHANGED=0

# 空行

# ----------------------------------------
# 步骤2：辅助函数：删除指定端口的所有 INPUT 规则
# ----------------------------------------

# 定义 delete_port_rules 函数
# 参数: $1 = 端口号
# 删除该端口的所有 INPUT 规则（可能有重复规则）
delete_port_rules() {
    # 接收端口参数
    local port="$1"
    
    # 使用 while 循环，每次删除一条匹配规则
    # iptables -D 删除规则
    # 如果规则存在，删除成功返回 0
    # 如果规则不存在，删除失败返回非 0
    # 2>/dev/null 丢弃错误输出
    while iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; do
        # 删除成功，记录日志
        # tee -a 同时输出到终端和追加到日志文件
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] 已删除 INPUT 规则（端口 $port）" | tee -a "$LOG_FILE"
        
        # 记录到系统日志
        logger -t "stop_router" "已删除 INPUT 规则（端口 $port）"
        
        # 标记有操作发生
        CHANGED=1
    done
    # 当 iptables -D 失败时（规则已不存在），while 循环自动退出
}
# 函数结束

# 空行

# ----------------------------------------
# 步骤3：从端口记录文件删除
# ----------------------------------------

# 定义 PORT_FILE 变量，值为端口记录文件路径
PORT_FILE="/tmp/natmap_router_port"

# 如果端口记录文件存在
if [ -f "$PORT_FILE" ]; then
    # 读取文件中的所有端口
    # cat 读取文件内容
    # sort -u 排序并去重（-u 表示 unique，去除重复行）
    for port in $(cat "$PORT_FILE" | sort -u); do
        # 调用删除函数，删除该端口的所有规则
        delete_port_rules "$port"
    done
    
    # 删除端口记录文件（清理）
    rm -f "$PORT_FILE"
fi

# 空行

# ----------------------------------------
# 步骤4：从 natmap 日志提取所有端口并删除
# ----------------------------------------

# 如果 natmap 日志文件存在
if [ -f "$LOG_FILE_NATMAP" ]; then
    # ---- 提取第5列（本地端口） ----
    # grep -E 使用扩展正则表达式
    # '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+' 匹配 "IP 端口" 格式的有效行
    # awk '{print $5}' 取第5列（本地端口）
    # while read port 逐行读取端口号
    grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+' "$LOG_FILE_NATMAP" | \
    awk '{print $5}' | while read port; do
        # 如果端口为空，跳过
        [ -z "$port" ] && continue
        # 删除该端口的所有规则
        delete_port_rules "$port"
    done
    
    # ---- 备选：提取第3列（公网端口，兼容旧日志格式） ----
    # 部分日志可能第5列为空（旧格式），备选取第3列
    grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+' "$LOG_FILE_NATMAP" | \
    awk '{print $3}' | while read port; do
        [ -z "$port" ] && continue
        delete_port_rules "$port"
    done
else
    # natmap 日志文件不存在，记录警告
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] 警告: natmap日志文件不存在，无法提取端口" | tee -a "$LOG_FILE"
    logger -t "stop_router" "警告: natmap日志文件不存在"
fi

# 空行

# ----------------------------------------
# 步骤5：停止 natmap 进程
# ----------------------------------------

# pgrep -f 查找匹配完整命令行的进程
# 匹配模式 "natmap.*172.16.10.1"
ROUTER_PID=$(pgrep -f "natmap.*172.16.10.1")

# 如果找到 PID（非空）
if [ -n "$ROUTER_PID" ]; then
    # kill 杀死进程，2>/dev/null 忽略错误
    kill $ROUTER_PID 2>/dev/null
    
    # 记录日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] 已停止 ROUTER natmap (PID: $ROUTER_PID)" | tee -a "$LOG_FILE"
    logger -t "stop_router" "已停止 ROUTER natmap (PID: $ROUTER_PID)"
    CHANGED=1
else
    # 进程未运行
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] ROUTER natmap 未运行，无需停止" | tee -a "$LOG_FILE"
    logger -t "stop_router" "ROUTER natmap 未运行，无需停止"
fi

# 空行

# ----------------------------------------
# 步骤6：停止 monitor_router.sh 进程
# ----------------------------------------

# pgrep -f 查找 monitor_router.sh 进程
MONITOR_PID=$(pgrep -f "monitor_router.sh")

if [ -n "$MONITOR_PID" ]; then
    kill $MONITOR_PID 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] 已停止 monitor_router.sh (PID: $MONITOR_PID)" | tee -a "$LOG_FILE"
    logger -t "stop_router" "已停止 monitor_router.sh (PID: $MONITOR_PID)"
    CHANGED=1
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] monitor_router.sh 未运行，无需停止" | tee -a "$LOG_FILE"
    logger -t "stop_router" "monitor_router.sh 未运行，无需停止"
fi

# 空行

# ----------------------------------------
# 步骤7：清理锁文件
# ----------------------------------------

# 删除锁文件，防止下次启动时认为脚本还在运行
rm -f /tmp/monitor_router.lock

# 空行

# ----------------------------------------
# 步骤8：输出总结信息
# ----------------------------------------

# 根据 CHANGED 标志判断是否执行了有效操作
if [ $CHANGED -eq 1 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] ROUTER的natmap相关进程处理完成，添加的防火墙规则已删除" | tee -a "$LOG_FILE"
    logger -t "stop_router" "ROUTER的natmap相关进程处理完成，添加的防火墙规则已删除"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [stop_router] ROUTER的natmap相关进程未运行，无需处理" | tee -a "$LOG_FILE"
    logger -t "stop_router" "ROUTER的natmap相关进程未运行，无需处理"
fi

# 脚本正常结束