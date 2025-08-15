#!/bin/bash
# Task Executor 监控和自动重启脚本

RAGFLOW_HOME="/data/ragflow-deployment/ragflow"
TASK_EXECUTOR_PID_FILE="$RAGFLOW_HOME/task_executor.pid"
LOG_DIR="$RAGFLOW_HOME/logs"
MONITOR_LOG="$LOG_DIR/task_executor_monitor.log"

cd "$RAGFLOW_HOME"

# 环境变量
export PYTHONPATH="$RAGFLOW_HOME"
export CUDA_VISIBLE_DEVICES=""

# 日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MONITOR_LOG"
}

# 检查task_executor是否运行
is_task_executor_running() {
    if [ -f "$TASK_EXECUTOR_PID_FILE" ]; then
        local pids=$(cat "$TASK_EXECUTOR_PID_FILE")
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                return 0
            fi
        done
    fi
    return 1
}

# 重启task_executor
restart_task_executor() {
    log_message "🔄 重启Task Executor..."
    
    # 清理旧的PID文件
    rm -f "$TASK_EXECUTOR_PID_FILE"
    
    # 启动新的task_executor
    nohup .venv/bin/python rag/svr/task_executor.py 0 > "$LOG_DIR/task_executor_0.log" 2>&1 &
    local new_pid=$!
    echo $new_pid > "$TASK_EXECUTOR_PID_FILE"
    
    sleep 3
    
    if kill -0 "$new_pid" 2>/dev/null; then
        log_message "✅ Task Executor重启成功 (PID: $new_pid)"
        return 0
    else
        log_message "❌ Task Executor重启失败"
        return 1
    fi
}

# 检查心跳活跃性
check_heartbeat() {
    local log_file="$LOG_DIR/task_executor_0.log"
    
    if [ ! -f "$log_file" ]; then
        return 1
    fi
    
    # 获取最后一次心跳时间
    local last_heartbeat=$(tail -100 "$log_file" | grep "reported heartbeat" | tail -1)
    
    if [ -z "$last_heartbeat" ]; then
        return 1
    fi
    
    # 提取时间戳
    local heartbeat_time=$(echo "$last_heartbeat" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}')
    
    if [ -z "$heartbeat_time" ]; then
        return 1
    fi
    
    # 转换为时间戳
    local heartbeat_timestamp=$(date -d "${heartbeat_time}" +%s 2>/dev/null)
    local current_timestamp=$(date +%s)
    
    if [ -z "$heartbeat_timestamp" ]; then
        return 1
    fi
    
    # 如果心跳超过5分钟没有更新，认为异常
    local diff=$((current_timestamp - heartbeat_timestamp))
    if [ $diff -gt 300 ]; then
        log_message "⚠️  心跳异常: 上次心跳 ${diff}秒前"
        return 1
    fi
    
    return 0
}

# 主监控循环
monitor_loop() {
    log_message "🔍 Task Executor监控启动"
    
    while true; do
        if ! is_task_executor_running; then
            log_message "❌ Task Executor进程不存在，正在重启..."
            restart_task_executor
        elif ! check_heartbeat; then
            log_message "💔 Task Executor心跳异常，正在重启..."
            # 先终止僵死进程
            if [ -f "$TASK_EXECUTOR_PID_FILE" ]; then
                local pids=$(cat "$TASK_EXECUTOR_PID_FILE")
                for pid in $pids; do
                    if kill -0 "$pid" 2>/dev/null; then
                        log_message "🛑 终止僵死进程 (PID: $pid)"
                        kill -KILL "$pid"
                    fi
                done
            fi
            restart_task_executor
        fi
        
        # 每分钟检查一次
        sleep 60
    done
}

# 处理信号
cleanup() {
    log_message "🛑 监控脚本退出"
    exit 0
}

trap cleanup SIGTERM SIGINT

# 确保日志目录存在
mkdir -p "$LOG_DIR"

case "${1:-monitor}" in
    start)
        if pgrep -f "monitor_task_executor.sh" > /dev/null; then
            echo "❌ 监控脚本已经在运行"
            exit 1
        fi
        nohup "$0" monitor > "$MONITOR_LOG" 2>&1 &
        echo "✅ Task Executor监控启动"
        echo "📋 监控日志: $MONITOR_LOG"
        ;;
    stop)
        if pkill -f "monitor_task_executor.sh"; then
            echo "✅ Task Executor监控已停止"
        else
            echo "📴 Task Executor监控未运行"
        fi
        ;;
    status)
        if pgrep -f "monitor_task_executor.sh" > /dev/null; then
            echo "🟢 Task Executor监控运行中"
            if [ -f "$MONITOR_LOG" ]; then
                echo "📋 最近日志:"
                tail -5 "$MONITOR_LOG"
            fi
        else
            echo "🔴 Task Executor监控未运行"
        fi
        ;;
    monitor)
        monitor_loop
        ;;
    *)
        echo "Task Executor 监控脚本"
        echo ""
        echo "用法: $0 {start|stop|status}"
        echo ""
        echo "命令说明:"
        echo "  start  - 启动监控"
        echo "  stop   - 停止监控"
        echo "  status - 查看监控状态"
        ;;
esac