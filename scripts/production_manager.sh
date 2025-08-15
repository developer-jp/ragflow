#!/bin/bash
# RAGFlow 生产环境管理脚本

set -e

# 配置
RAGFLOW_HOME="/data/ragflow-deployment/ragflow"
PID_FILE="$RAGFLOW_HOME/ragflow_production.pid"
TASK_EXECUTOR_PID_FILE="$RAGFLOW_HOME/task_executor.pid"
LOG_DIR="$RAGFLOW_HOME/logs"
STARTUP_SCRIPT="$RAGFLOW_HOME/scripts/start_production_simple.py"
TASK_EXECUTOR_COUNT=1  # 任务执行器数量
MONITOR_SCRIPT="$RAGFLOW_HOME/scripts/monitor_task_executor.sh"

# 环境变量
export PYTHONPATH="$RAGFLOW_HOME"
export CUDA_VISIBLE_DEVICES=""  # RTX 5090兼容性问题

cd "$RAGFLOW_HOME"

# 函数定义
get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE"
    fi
}

is_running() {
    local pid=$(get_pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

get_task_executor_pids() {
    if [ -f "$TASK_EXECUTOR_PID_FILE" ]; then
        cat "$TASK_EXECUTOR_PID_FILE"
    fi
}

is_task_executor_running() {
    local pids=$(get_task_executor_pids)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                return 0
            fi
        done
    fi
    return 1
}

start_ragflow() {
    if is_running; then
        echo "❌ RAGFlow已经在运行中 (PID: $(get_pid))"
        return 1
    fi

    echo "🔍 检查依赖服务..."
    
    # 检查Elasticsearch
    if ! curl -s http://localhost:1200/_health > /dev/null 2>&1; then
        echo "❌ Elasticsearch未运行 (端口1200)"
        exit 1
    fi
    echo "✅ Elasticsearch运行正常"
    
    # 检查Ollama
    if ! curl -s http://localhost:11434/api/ps > /dev/null 2>&1; then
        echo "⚠️  Ollama未运行，LLM功能将不可用"
    else
        echo "✅ Ollama运行正常"
        # 显示加载的模型
        models=$(curl -s http://localhost:11434/api/ps | jq -r '.models[].name' 2>/dev/null || echo "无")
        echo "📦 已加载模型: $models"
    fi
    
    echo "🚀 启动RAGFlow生产服务器..."
    mkdir -p "$LOG_DIR"
    
    # 使用原始方法启动RAGFlow (避免JWT认证问题)
    nohup .venv/bin/python api/ragflow_server.py > ragflow.log 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"
    
    # 等待启动
    sleep 8
    
    if is_running; then
        echo "✅ RAGFlow API服务器启动成功!"
        
        # 启动task_executor
        echo "🚀 启动Task Executor..."
        > "$TASK_EXECUTOR_PID_FILE"  # 清空PID文件
        
        for ((i=0; i<$TASK_EXECUTOR_COUNT; i++)); do
            nohup .venv/bin/python rag/svr/task_executor.py $i > "$LOG_DIR/task_executor_$i.log" 2>&1 &
            local task_pid=$!
            echo $task_pid >> "$TASK_EXECUTOR_PID_FILE"
            echo "   Task Executor $i 启动 (PID: $task_pid)"
        done
        
        sleep 3
        
        if is_task_executor_running; then
            echo "✅ Task Executor启动成功!"
            
            # 启动监控
            echo "🔍 启动Task Executor监控..."
            "$MONITOR_SCRIPT" start
        else
            echo "⚠️  Task Executor启动失败，PDF解析功能将不可用"
        fi
        
        echo "🌐 访问地址: http://localhost:9380"
        echo "📂 日志目录: $LOG_DIR"
        echo "🔧 API进程ID: $(get_pid)"
        echo "🔧 Task Executor PIDs: $(get_task_executor_pids | tr '\n' ' ')"
        echo "💾 内存使用: $(ps -o rss= -p $(get_pid) 2>/dev/null | awk '{print $1/1024 "MB"}' || echo '未知')"
    else
        echo "❌ RAGFlow启动失败，请查看日志:"
        echo "   tail -50 $LOG_DIR/startup.log"
        rm -f "$PID_FILE"
        exit 1
    fi
}

stop_ragflow() {
    local has_service=false
    
    # 停止Task Executor
    if is_task_executor_running; then
        has_service=true
        local task_pids=$(get_task_executor_pids)
        echo "🛑 停止Task Executor进程..."
        for pid in $task_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "   停止Task Executor (PID: $pid)"
                kill -TERM "$pid"
            fi
        done
        
        # 等待Task Executor停止
        sleep 2
        for pid in $task_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "   强制终止Task Executor (PID: $pid)"
                kill -KILL "$pid"
            fi
        done
        rm -f "$TASK_EXECUTOR_PID_FILE"
    fi
    
    # 停止监控
    if [ -f "$MONITOR_SCRIPT" ]; then
        echo "🛑 停止Task Executor监控..."
        "$MONITOR_SCRIPT" stop
    fi
    
    # 停止API服务器
    if ! is_running; then
        if [ "$has_service" = false ]; then
            echo "📴 RAGFlow未运行"
        fi
        rm -f "$PID_FILE"
        return 0
    fi
    
    has_service=true
    local pid=$(get_pid)
    echo "🛑 停止RAGFlow API服务器 (PID: $pid)..."
    
    # 优雅关闭
    kill -TERM "$pid"
    
    # 等待最多30秒
    local count=0
    while [ $count -lt 30 ] && is_running; do
        sleep 1
        count=$((count + 1))
        echo -n "."
    done
    echo
    
    if is_running; then
        echo "⚠️  优雅关闭超时，强制终止..."
        kill -KILL "$pid"
        sleep 2
    fi
    
    if ! is_running; then
        echo "✅ RAGFlow已停止"
        rm -f "$PID_FILE"
    else
        echo "❌ 无法停止RAGFlow进程"
        exit 1
    fi
}

status_ragflow() {
    local has_service=false
    
    if is_running; then
        has_service=true
        local pid=$(get_pid)
        local memory=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1/1024 "MB"}' || echo '未知')
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo '未知')
        
        echo "🟢 RAGFlow运行状态:"
        echo "📡 API服务器:"
        echo "   进程ID: $pid"
        echo "   运行时间: $uptime"
        echo "   内存使用: $memory"
        echo "   访问地址: http://localhost:9380"
        
        # 测试API响应
        if curl -s http://localhost:9380/ >/dev/null 2>&1; then
            echo "   API状态: ✅ 响应正常"
        else
            echo "   API状态: ❌ 无响应"
        fi
        
        # 检查Task Executor状态
        echo ""
        if is_task_executor_running; then
            echo "⚙️  Task Executor:"
            local task_pids=$(get_task_executor_pids)
            local i=0
            for pid in $task_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    local task_memory=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1/1024 "MB"}' || echo '未知')
                    local task_uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo '未知')
                    echo "   Task Executor $i: PID=$pid, 内存=$task_memory, 运行时间=$task_uptime"
                    
                    # 检查最新的心跳日志
                    if [ -f "$LOG_DIR/task_executor_$i.log" ]; then
                        local heartbeat=$(tail -1 "$LOG_DIR/task_executor_$i.log" | grep -o '"pending": [0-9]*' | cut -d' ' -f2 || echo '')
                        if [ -n "$heartbeat" ]; then
                            echo "      待处理任务: $heartbeat"
                        fi
                    fi
                else
                    echo "   Task Executor $i: ❌ 已停止"
                fi
                i=$((i+1))
            done
        else
            echo "⚠️  Task Executor: 未运行 (PDF解析功能不可用)"
        fi
        
        # 检查监控状态
        echo ""
        if [ -f "$MONITOR_SCRIPT" ]; then
            "$MONITOR_SCRIPT" status
        fi
        
        # 检查Ollama模型状态
        echo ""
        local models=$(curl -s http://localhost:11434/api/ps 2>/dev/null | jq -r '.models[]?.name' 2>/dev/null || echo '')
        if [ -n "$models" ]; then
            echo "🤖 Ollama模型: $models"
        fi
        
    else
        if is_task_executor_running; then
            has_service=true
            echo "⚠️  RAGFlow API服务器未运行"
            echo "⚙️  Task Executor状态:"
            local task_pids=$(get_task_executor_pids)
            for pid in $task_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    echo "   PID $pid: 运行中 (但API服务器未运行)"
                fi
            done
        fi
        
        if [ "$has_service" = false ]; then
            echo "🔴 RAGFlow未运行"
        fi
        rm -f "$PID_FILE"
    fi
}

restart_ragflow() {
    echo "🔄 重启RAGFlow服务..."
    stop_ragflow
    sleep 3
    start_ragflow
}

logs_ragflow() {
    if [ ! -f "$LOG_DIR/startup.log" ]; then
        echo "❌ 日志文件不存在: $LOG_DIR/startup.log"
        exit 1
    fi
    
    echo "📋 RAGFlow日志 (最近50行):"
    echo "----------------------------------------"
    tail -50 "$LOG_DIR/startup.log"
    echo "----------------------------------------"
    echo "💡 实时日志: tail -f $LOG_DIR/startup.log"
}

# 主逻辑
case "${1:-status}" in
    start)
        start_ragflow
        ;;
    stop)
        stop_ragflow
        ;;
    restart)
        restart_ragflow
        ;;
    status)
        status_ragflow
        ;;
    logs)
        logs_ragflow
        ;;
    monitor)
        if [ -f "$MONITOR_SCRIPT" ]; then
            "$MONITOR_SCRIPT" "${2:-status}"
        else
            echo "❌ 监控脚本不存在"
        fi
        ;;
    *)
        echo "RAGFlow 生产环境管理脚本"
        echo ""
        echo "用法: $0 {start|stop|restart|status|logs|monitor}"
        echo ""
        echo "命令说明:"
        echo "  start   - 启动RAGFlow服务"
        echo "  stop    - 停止RAGFlow服务"  
        echo "  restart - 重启RAGFlow服务"
        echo "  status  - 查看服务状态"
        echo "  logs    - 查看服务日志"
        echo ""
        echo "例子:"
        echo "  $0 start    # 启动服务"
        echo "  $0 status   # 查看状态"
        echo "  $0 logs     # 查看日志"
        exit 1
        ;;
esac