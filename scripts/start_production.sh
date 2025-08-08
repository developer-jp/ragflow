#!/bin/bash
# RAGFlow 生产环境启动脚本

set -e

# 配置
RAGFLOW_HOME="/data/ragflow-deployment/ragflow"
LOG_FILE="$RAGFLOW_HOME/ragflow.log"
PID_FILE="$RAGFLOW_HOME/ragflow.pid"

# 环境变量
export PYTHONPATH="$RAGFLOW_HOME"
export CUDA_VISIBLE_DEVICES=""  # RTX 5090兼容性问题，使用CPU模式

# 函数
start_ragflow() {
    echo "正在启动RAGFlow..."
    cd "$RAGFLOW_HOME"
    
    # 检查依赖服务
    if ! curl -s http://localhost:1200/_health > /dev/null; then
        echo "错误: Elasticsearch未运行"
        exit 1
    fi
    
    if ! curl -s http://localhost:11434/api/ps > /dev/null; then
        echo "警告: Ollama未运行，LLM功能将不可用"
    fi
    
    # 启动服务
    nohup .venv/bin/python api/ragflow_server.py > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    
    sleep 5
    if ps -p $(cat "$PID_FILE") > /dev/null; then
        echo "RAGFlow已启动 (PID: $(cat "$PID_FILE"))"
        echo "Web界面: http://localhost:9380"
        echo "日志文件: $LOG_FILE"
    else
        echo "RAGFlow启动失败，请检查日志: $LOG_FILE"
        exit 1
    fi
}

stop_ragflow() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null; then
            echo "正在停止RAGFlow (PID: $PID)..."
            kill -TERM $PID
            sleep 5
            if ps -p $PID > /dev/null; then
                echo "强制停止RAGFlow..."
                kill -KILL $PID
            fi
        fi
        rm -f "$PID_FILE"
        echo "RAGFlow已停止"
    else
        echo "RAGFlow未运行"
    fi
}

status_ragflow() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null; then
            echo "RAGFlow正在运行 (PID: $PID)"
            echo "内存使用: $(ps -o rss= -p $PID | awk '{print $1/1024 "MB"}')"
            curl -s http://localhost:9380/v1/system/version | jq .
        else
            echo "RAGFlow进程已停止，但PID文件存在"
            rm -f "$PID_FILE"
        fi
    else
        echo "RAGFlow未运行"
    fi
}

# 主逻辑
case "$1" in
    start)
        start_ragflow
        ;;
    stop)
        stop_ragflow
        ;;
    restart)
        stop_ragflow
        sleep 2
        start_ragflow
        ;;
    status)
        status_ragflow
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        echo "例子:"
        echo "  $0 start   # 启动RAGFlow"
        echo "  $0 stop    # 停止RAGFlow"
        echo "  $0 restart # 重启RAGFlow"
        echo "  $0 status  # 查看状态"
        exit 1
        ;;
esac