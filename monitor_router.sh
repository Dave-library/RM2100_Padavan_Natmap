#!/bin/sh
# 这行是 shebang，指定使用 /bin/sh 作为解释器执行本脚本
# /bin/sh 是 POSIX 兼容的 shell，在 Padavan 系统中指向 busybox 的 ash

# 空行，用于分隔文件头说明和实际代码

# =============================================================================
# 这一行是注释分隔线，用于视觉上划分代码块
# 脚本名称: monitor_router.sh
# 用途: 监控 ROUTER 服务 (172.16.10.1:5001) 的 natmap 日志
#       动态管理防火墙 INPUT 规则，端口稳定后发送微信推送
#       自动巡检防火墙规则，缺失时自动补充
#       增加原因文件时效性判断（120秒内有效），避免复用旧原因
# 目录: /etc/storage/bin/natmap/router/
# 依赖: iptables, pgrep, flock, logger, date, awk, grep, sed, stat
# =============================================================================
# 注释分隔线结束

# 空行，分隔文件头说明和实际代码

# ----------------------------------------
# 这一行是注释分隔线，标记步骤1的开始
# 步骤1：防止重复运行（锁机制）
# ----------------------------------------
# 步骤1注释结束

# 定义锁文件路径，存储在 /tmp 临时目录
# 锁文件用于防止多个实例同时运行
LOCK_FILE="/tmp/monitor_router.lock"

# 打开文件描述符 200，以写入方式指向锁文件
# exec 是 shell 内置命令，用于重定向当前 shell 的文件描述符
# 200 是文件描述符编号（大于 2 的编号可用于自定义）
# > 以写入方式打开，如果文件不存在则创建
# 这样可以在整个脚本生命周期内持有这个文件句柄
exec 200>"$LOCK_FILE"

# flock 是文件锁工具，用于管理文件锁
# -n 表示非阻塞模式（non-blocking）
# 如果无法获取锁，立即失败返回非 0，不等待
# 200 是文件描述符编号，指向锁文件
# || exit 1 表示如果 flock 失败（返回非 0），则执行 exit 1 退出脚本
# 这样可以确保同一时间只有一个脚本实例在运行
flock -n 200 || exit 1

# 注意：脚本退出时文件描述符会自动关闭，锁自动释放
# 所以不需要显式释放锁

# 空行，分隔步骤1和步骤2

# ----------------------------------------
# 这一行是注释分隔线，标记步骤2的开始
# 步骤2：配置参数
# ----------------------------------------
# 步骤2注释结束

# 定义 LOG 变量，值为 natmap 日志文件路径
# 这个文件由 natmap 程序写入，包含公网 IP 和端口信息
# 监控脚本从这个文件读取数据
LOG="/etc/storage/bin/natmap/router/logs/router_natmap.log"

# 定义 LAST_PORT 变量，值为空字符串
# 用于记录上次检测到的本地端口，检测端口是否变化
# 初始为空，表示尚未记录任何端口
LAST_PORT=""

# 定义 IPTABLES 变量，值为 iptables 命令的完整路径
# 用于管理防火墙规则
IPTABLES="/bin/iptables"

# 定义 COUNT_FILE 变量，值为消息计数文件路径
# 用于记录当天推送的消息条数，显示在推送标题中
# 每天自动重置
COUNT_FILE="/etc/storage/natmap_msg_count_router.txt"

# 定义 PORT_FILE 变量，值为当前放行端口记录文件路径
# 存储当前防火墙放行的端口号，供其他脚本（如 stop_router.sh）读取
# 也用于防火墙规则巡检
PORT_FILE="/tmp/natmap_router_port"

# 空行，分隔配置参数和防重复推送变量

# ---------- 防重复推送变量 ----------
# 这一行注释标记防重复推送变量的开始

# 定义 last_pushed_port 变量，值为空字符串
# 用于存储上次推送的端口号，判断是否重复
last_pushed_port=""

# 定义 last_push_time 变量，值为 0
# 用于存储上次推送的时间戳（秒）
# 配合端口号判断 60 秒内是否重复推送
last_push_time=0

# 空行，分隔步骤2和步骤3

# ----------------------------------------
# 这一行是注释分隔线，标记步骤3的开始
# 步骤3：获取 WAN 口 IP
# ----------------------------------------
# 步骤3注释结束

# 定义 get_wan_ip 函数，获取路由器的 WAN 口公网 IP
# 函数没有参数，成功返回 IP 字符串，失败返回 "无法获取"
get_wan_ip() {
    # 这是函数体的开始，左花括号
    
    # 方法一：从 ppp0 接口获取
    # ifconfig ppp0 显示 ppp0 网络接口信息
    # 2>/dev/null 丢弃错误输出（接口不存在时）
    # grep 'inet addr' 过滤包含 IP 地址的行
    # awk -F: 以冒号为分隔符，取第2字段（IP:xxx.xxx.xxx.xxx）
    # 第二个 awk '{print $1}' 取第一个单词（纯 IP 地址）
    local ip=$(ifconfig ppp0 2>/dev/null | grep 'inet addr' | awk -F: '{print $2}' | awk '{print $1}')
    
    # [ -n "$ip" ] 判断 ip 变量是否非空
    # && echo "$ip" 如果非空，输出 IP 并返回
    # && return 返回，不执行后面的代码
    [ -n "$ip" ] && echo "$ip" && return
    
    # 方法二：备用获取方式（通过路由表获取网卡名）
    # ip route get 1 获取到任意地址的路由信息
    # awk '{print $5; exit}' 提取第5列（网卡名称）并立即退出
    # xargs -I {} 将输出的网卡名作为参数传给 ifconfig
    # ifconfig {} 显示该网卡信息，再用同样的方式提取 IP
    ip=$(ip route get 1 2>/dev/null | awk '{print $5; exit}' | xargs -I {} ifconfig {} 2>/dev/null | grep 'inet addr' | awk -F: '{print $2}' | awk '{print $1}')
    
    # 如果还是空，输出"无法获取"，否则输出 IP
    # [ -n "$ip" ] 判断是否非空
    # && echo "$ip" 非空则输出 IP
    # || echo "无法获取" 空则输出 "无法获取"
    [ -n "$ip" ] && echo "$ip" || echo "无法获取"
}
# 这是函数体的结束，右花括号

# 空行，分隔步骤3和步骤4

# ----------------------------------------
# 这一行是注释分隔线，标记步骤4的开始
# 步骤4：获取当天消息序号
# ----------------------------------------
# 步骤4注释结束

# 定义 get_msg_number 函数，获取当天已推送消息的序号
# 每天重置为 1，每次调用自动加 1
# 返回值：当天的消息序号（数字）
get_msg_number() {
    # 这是函数体的开始，左花括号
    
    # date '+%Y-%m-%d' 获取当天日期，格式如 "2026-07-09"
    TODAY=$(date '+%Y-%m-%d')
    
    # 空行，分隔日期获取和文件检查
    
    # if [ ! -f "$COUNT_FILE" ] 判断计数文件是否不存在
    if [ ! -f "$COUNT_FILE" ]; then
        # 文件不存在，创建新文件
        # 写入 "日期|1"，如 "2026-07-09|1"
        echo "$TODAY|1" > "$COUNT_FILE"
        # echo "1" 返回 1（第一天第一次推送）
        echo "1"
        # return 退出函数
        return
    fi
    # if 语句结束
    
    # 空行，分隔文件创建和读取
    
    # cut -d'|' -f1 以 | 为分隔符，取第1字段（日期）
    SAVED_DATE=$(cut -d'|' -f1 "$COUNT_FILE")
    
    # cut -d'|' -f2 以 | 为分隔符，取第2字段（计数）
    SAVED_COUNT=$(cut -d'|' -f2 "$COUNT_FILE")
    
    # 空行，分隔读取和判断
    
    # 如果保存的日期不是今天
    if [ "$SAVED_DATE" != "$TODAY" ]; then
        # 重置为今天和计数 1
        echo "$TODAY|1" > "$COUNT_FILE"
        # 返回 1
        echo "1"
    else
        # 如果是今天，计数加 1
        NEW_COUNT=$((SAVED_COUNT + 1))
        # 写入更新后的计数
        echo "$TODAY|$NEW_COUNT" > "$COUNT_FILE"
        # 返回新计数
        echo "$NEW_COUNT"
    fi
    # 内层 if 语句结束
}
# 函数体的结束，右花括号

# 空行，分隔步骤4和步骤5

# ----------------------------------------
# 这一行是注释分隔线，标记步骤5的开始
# 步骤5：发送微信推送
# ----------------------------------------
# 步骤5注释结束

# 定义 send_push 函数，发送微信推送通知
# 参数列表：
#   $1 = ip        公网 IP（从 natmap 日志提取）
#   $2 = wan_port  公网端口（从 natmap 日志提取）
#   $3 = local_port 本地端口（从 natmap 日志提取，防火墙放行的端口）
#   $4 = wan_ip    出口 WAN IP（路由器的 WAN 口 IP）
send_push() {
    # 函数体开始，左花括号
    
    # 将参数赋值给有意义的变量名
    # local 声明局部变量
    local ip="$1"
    local wan_port="$2"
    local local_port="$3"
    local wan_ip="$4"
    
    # 空行，分隔参数赋值和序号获取
    
    # 调用 get_msg_number 函数获取当天消息序号
    local num=$(get_msg_number)
    
    # 空行，分隔序号获取和原因处理
    
    # ★★★ 修改：增加原因文件时效性判断（120秒内有效） ★★★
    # 原因：端口变化时不应复用旧的 IP 变化原因（如"定时重启"）
    # 只有 IP 刚变化（120秒内）才使用动态原因，否则使用固定原因
    # 120秒覆盖从 IP 变化到端口稳定推送的完整流程
    # 包括：写入原因文件 → 杀死旧 natmap → 启动新 natmap →
    #       natmap 写入日志 → monitor 检测到变化 → 等待20秒确认稳定
    
    # 初始化 reason 为固定值 "端口映射重新分配"
    # 这个值是默认值，只有在原因文件有效时才会被覆盖
    local reason="端口映射重新分配"
    
    # 定义原因文件路径，由 check_ip_change.sh 写入
    # 文件路径为 /tmp/ip_change_reason_router
    local REASON_FILE="/tmp/ip_change_reason_router"
    
    # if [ -f "$REASON_FILE" ] 判断原因文件是否存在
    if [ -f "$REASON_FILE" ]; then
        # 文件存在，检查其修改时间
        # stat -c %Y 获取文件的最后修改时间戳（秒）
        # 2>/dev/null 丢弃错误输出（如文件不存在或 stat 不支持）
        file_time=$(stat -c %Y "$REASON_FILE" 2>/dev/null)
        
        # date +%s 获取当前时间戳（秒）
        current_time=$(date +%s)
        
        # 判断文件是否在 120 秒内写入
        # [ -n "$file_time" ] 确保 file_time 非空（stat 执行成功）
        # $((current_time - file_time)) 计算时间差
        # -lt 120 判断是否小于 120 秒
        if [ -n "$file_time" ] && [ $((current_time - file_time)) -lt 120 ]; then
            # 文件在 120 秒内写入，说明是本次 IP 变化产生的
            # 读取文件内容作为变化原因
            reason=$(cat "$REASON_FILE")
        fi
        # 内层 if 结束
        # 否则文件太旧（超过120秒），保持固定原因"端口映射重新分配"
    fi
    # 外层 if 结束
    # 如果原因文件不存在，同样使用固定原因"端口映射重新分配"
    
    # 空行，分隔原因处理和标题组装
    
    # 组装推送标题
    # [ROUTER] 是固定标签，表示来自 ROUTER 服务
    # 第${num}条 表示当天第几次推送
    local title="[ROUTER] 端口更新成功 (第${num}条)"
    
    # 空行，分隔标题和内容组装
    
    # 组装推送内容
    # 注意：这里使用真实的换行符，不是 \n 字符串
    # 微信推送脚本会原样发送这些内容
    # 内容包含：公网地址、出口地址、本地地址、变化原因
    local content="公网地址: ${ip}:${wan_port}
出口地址: ${wan_ip}:${local_port}
本地地址: 172.16.10.1:5001
变化原因: ${reason}"
    
    # 空行，分隔内容组装和防重复检查
    
    # date +%s 获取当前时间戳（秒）
    current_time=$(date +%s)
    
    # 防重复推送检查
    # 条件1：当前端口与上次推送端口相同
    # 条件2：距离上次推送不到 60 秒
    # && 逻辑与，两个条件都满足才执行
    if [ "$local_port" = "$last_pushed_port" ] && [ $((current_time - last_push_time)) -lt 60 ]; then
        # 满足防重复条件，记录忽略信息到系统日志
        logger -t "monitor_router" "忽略重复推送: router 出口地址端口: -> $local_port"
        # return 返回，不执行推送
        return
    fi
    # if 语句结束
    
    # 空行，分隔防重复检查和推送执行
    
    # 检查微信推送脚本是否存在且可执行
    # -x 测试文件是否存在且具有可执行权限
    if [ -x "/etc/storage/script/Sh45_wx_send.sh" ]; then
        # 推送脚本存在且可执行，调用它
        # 传递两个参数：标题和内容
        /etc/storage/script/Sh45_wx_send.sh send_message "$title" "$content"
        
        # 记录推送成功到系统日志（复杂版：区分公网和出口）
        # 第一条：公网地址和端口
        logger -t "monitor_router" "已发送微信推送: router 公网地址和端口: -> ${ip} : ${wan_port}"
        # 第二条：出口地址和端口
        logger -t "monitor_router" "已发送微信推送: router 出口地址和端口: -> ${wan_ip} : ${local_port}"
        
        # 更新推送记录（用于防重复）
        last_pushed_port="$local_port"
        last_push_time=$current_time
    else
        # 推送脚本不存在或无执行权限，记录错误
        logger -t "monitor_router" "错误: 微信推送脚本不存在或无执行权限"
    fi
    # 内层 if 语句结束
}
# 函数体的结束，右花括号

# 空行，分隔步骤5和步骤6

# ----------------------------------------
# 这一行是注释分隔线，标记步骤6的开始
# 步骤6：防火墙规则巡检与自动补充
# ----------------------------------------
# 步骤6注释结束

# 定义 check_and_fix_firewall 函数
# 定期检查防火墙规则是否存在，缺失则自动补充
# 这是自动修复机制的核心函数
check_and_fix_firewall() {
    # 函数体开始，左花括号
    
    # 检查端口记录文件是否存在
    if [ ! -f "$PORT_FILE" ]; then
        # 文件不存在，说明还没有记录任何端口（初次运行）
        # 直接返回，不执行任何操作
        return
    fi
    # if 语句结束
    
    # 空行，分隔文件检查和读取
    
    # 读取文件中记录的端口号
    # cat 读取文件内容
    # tr -d ' \n' 删除所有空格和换行符，确保得到纯数字
    # 防止文件中有多余的空白字符
    local expected_port=$(cat "$PORT_FILE" | tr -d ' \n')
    
    # 如果端口号为空，返回
    [ -z "$expected_port" ] && return
    
    # 空行，分隔读取和规则检查
    
    # 检查该端口的防火墙规则是否存在
    # iptables -C 检查规则是否存在（-C 表示 Check）
    # -C 是 iptables 的检查模式，不修改规则
    # 如果规则存在，返回 0；不存在，返回非 0
    # 2>/dev/null 丢弃错误输出
    if ! $IPTABLES -C INPUT -p tcp --dport "$expected_port" -j ACCEPT 2>/dev/null; then
        # 规则不存在，重新添加
        # iptables -A 追加规则到指定链
        # INPUT 链是输入链，处理进入本机的数据包
        # -p tcp 指定协议为 TCP
        # --dport 指定目标端口
        # -j ACCEPT 指定动作为允许（接受）
        $IPTABLES -A INPUT -p tcp --dport "$expected_port" -j ACCEPT
        
        # 记录补充操作到系统日志
        logger -t "monitor_router" "防火墙 INPUT 规则缺失，已自动补充: router 出口地址端口: -> $expected_port"
    fi
    # if 语句结束
}
# 函数体的结束，右花括号

# 空行，分隔步骤6和步骤7

# ----------------------------------------
# 这一行是注释分隔线，标记步骤7的开始
# 步骤7：处理 natmap 日志
# ----------------------------------------
# 步骤7注释结束

# 定义 process_log 函数，这是核心处理逻辑
# 监控 natmap 日志，检测端口变化，更新防火墙规则，发送推送
process_log() {
    # 函数体开始，左花括号
    
    # 如果日志文件不存在，直接返回
    # ! -f 测试文件是否不存在
    [ ! -f "$LOG" ] && return
    
    # 空行，分隔文件检查和日志提取
    
    # 提取最新一条包含公网 IP 的日志行
    # tail -n 10 取文件最后 10 行（避免漏掉最新数据）
    # grep -E 使用扩展正则表达式
    # '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' 匹配 IPv4 地址格式
    # tail -1 取匹配结果的最后一行（最新的一条）
    LINE=$(tail -n 10 "$LOG" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
    
    # 如果没有匹配到任何行，返回
    [ -z "$LINE" ] && return
    
    # 空行，分隔日志提取和解析
    
    # 解析日志行
    # 日志格式示例：
    # 2026-07-09 00:12:15 203.0.113.5 43536 172.16.10.1 63964 tcp 172.16.10.1
    # 列序号说明：
    #   $1 = 日期       (2026-07-09)
    #   $2 = 时间       (00:12:15)
    #   $3 = 公网 IP    (203.0.113.5)
    #   $4 = 公网端口   (43536)
    #   $5 = 内网 IP    (172.16.10.1) - 目标
    #   $6 = 本地端口   (63964)
    #   $7 = 协议       (tcp)
    #   $8 = 内网 IP    (172.16.10.1) - 来源
    
    # 提取公网 IP（第3列）
    IP=$(echo "$LINE" | awk '{print $3}')
    
    # 提取公网端口（第4列）
    WAN_PORT=$(echo "$LINE" | awk '{print $4}')
    
    # 提取本地端口（优先第6列）
    LOCAL_PORT=$(echo "$LINE" | awk '{print $6}')
    
    # 如果第6列为空，尝试第5列（兼容旧日志格式）
    [ -z "$LOCAL_PORT" ] && LOCAL_PORT=$(echo "$LINE" | awk '{print $5}')
    
    # 如果还是空，使用公网端口（最保守的兜底方案）
    [ -z "$LOCAL_PORT" ] && LOCAL_PORT="$WAN_PORT"
    
    # 空行，分隔解析和验证
    
    # 如果 IP 或 WAN_PORT 为空，返回（数据不完整）
    [ -z "$IP" ] || [ -z "$WAN_PORT" ] && return
    
    # 如果端口与上次记录相同，返回（无变化，不需要处理）
    [ "$LOCAL_PORT" = "$LAST_PORT" ] && return
    
    # 获取 WAN 口 IP（用于日志输出）
    WAN_IP=$(get_wan_ip)
    
    # ---- 端口有变化，开始更新流程 ----
    # 记录端口变化到系统日志（复杂版：区分公网和出口）
    # 第一条：公网地址和端口变化
    logger -t "monitor_router" "检测到 router 公网地址和端口变化: $LAST_PORT -> ${IP} : ${WAN_PORT}，等待20秒确认稳定..."
    # 第二条：出口地址和端口变化
    logger -t "monitor_router" "检测到 router 出口地址和端口变化: $LAST_PORT -> ${WAN_IP} : ${LOCAL_PORT}，等待20秒确认稳定..."
    
    # 空行，分隔日志和等待
    
    # 等待 20 秒确保端口稳定（避免频繁变化导致误操作）
    # 如果端口在 20 秒内再次变化，后续的二次验证会检测到
    sleep 20
    
    # ---- 二次验证 ----
    # 再次提取最新一条记录进行确认
    LINE2=$(tail -n 10 "$LOG" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
    [ -z "$LINE2" ] && return
    
    # 空行，分隔提取和解析
    
    # 解析第二次提取的日志行
    IP2=$(echo "$LINE2" | awk '{print $3}')
    WAN_PORT2=$(echo "$LINE2" | awk '{print $4}')
    LOCAL_PORT2=$(echo "$LINE2" | awk '{print $6}')
    [ -z "$LOCAL_PORT2" ] && LOCAL_PORT2=$(echo "$LINE2" | awk '{print $5}')
    [ -z "$LOCAL_PORT2" ] && LOCAL_PORT2="$WAN_PORT2"
    
    # 空行，分隔解析和稳定性判断
    
    # 验证稳定性：如果第二次提取的端口与第一次不同，说明不稳定
    # 或者 IP 不同，说明网络变化
    # || 逻辑或，任一条件成立则放弃
    if [ "$LOCAL_PORT2" != "$LOCAL_PORT" ] || [ "$IP2" != "$IP" ]; then
        logger -t "monitor_router" "端口不稳定或 IP 变化，放弃本次更新"
        return
    fi
    # if 语句结束
    
    # ---- 更新防火墙规则 ----
    # 如果之前有旧端口记录，先删除旧规则
    # [ -n "$LAST_PORT" ] 判断 LAST_PORT 是否非空
    if [ -n "$LAST_PORT" ]; then
        # iptables -D 删除规则
        # 2>/dev/null 忽略错误（规则可能已不存在）
        $IPTABLES -D INPUT -p tcp --dport "$LAST_PORT" -j ACCEPT 2>/dev/null
    fi
    # if 语句结束
    
    # 添加新端口规则到防火墙
    $IPTABLES -A INPUT -p tcp --dport "$LOCAL_PORT" -j ACCEPT
    
    # 空行，分隔规则添加和记录
    
    # 将新端口写入端口记录文件
    echo "$LOCAL_PORT" > "$PORT_FILE"
    
    # 记录防火墙规则更新到系统日志
    logger -t "monitor_router" "防火墙 INPUT 规则已添加: router 出口地址端口: -> $LOCAL_PORT"
    
    # ---- 发送微信推送 ----
    # 调用 send_push 函数发送推送
    send_push "$IP" "$WAN_PORT" "$LOCAL_PORT" "$WAN_IP"
    
    # 更新最后记录的端口
    LAST_PORT="$LOCAL_PORT"
}
# 函数体的结束，右花括号

# 空行，分隔步骤7和步骤8

# ----------------------------------------
# 这一行是注释分隔线，标记步骤8的开始
# 步骤8：启动延迟
# ----------------------------------------
# 步骤8注释结束

# 记录脚本启动信息到系统日志
logger -t "monitor_router" "脚本启动，等待 20 秒让 natmap 完成初始化..."

# 等待 20 秒让 natmap 有足够时间生成初始日志
# 避免启动时读取到不完整的日志
sleep 20

# 空行，分隔步骤8和步骤9

# ----------------------------------------
# 这一行是注释分隔线，标记步骤9的开始
# 步骤9：主循环
# ----------------------------------------
# 步骤9注释结束

# while true 无限循环，脚本持续运行
while true; do
    # 循环体开始，左花括号
    
    # 先执行规则巡检与修复（确保防火墙规则存在）
    # 这是自动修复功能，即使端口没有变化，也会检查规则
    check_and_fix_firewall
    
    # 再处理日志变化（检测端口变化并更新）
    process_log
    
    # 休眠 15 秒后进入下一轮循环
    # 15 秒是巡检间隔，平衡实时性和系统负载
    sleep 15
done
# while 循环结束

# 脚本结束
# 这一行是文件末尾，没有实际代码