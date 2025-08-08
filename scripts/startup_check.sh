#!/bin/bash
# RAGFlow 启动检查和修复脚本

set -e

RAGFLOW_HOME="/data/ragflow-deployment/ragflow"
LOG_FILE="/var/log/ragflow-startup.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查 Docker 服务
check_docker() {
    if ! systemctl is-active --quiet docker; then
        log "Starting Docker service..."
        systemctl start docker
        sleep 10
    fi
    log "✅ Docker service is running"
}

# 检查 Ollama 服务
check_ollama() {
    if ! systemctl is-active --quiet ollama; then
        log "Starting Ollama service..."
        systemctl start ollama
        sleep 20
    fi
    
    # 等待 Ollama 完全启动
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/tags &>/dev/null; then
            log "✅ Ollama service is running"
            
            # 检查模型是否存在
            if ollama list | grep -q "gemma3-optimized"; then
                log "✅ Ollama model gemma3-optimized is loaded"
            else
                log "⚠️ Model gemma3-optimized not found, creating..."
                cd /tmp
                cat > optimized.modelfile << 'EOF'
FROM gemma3:27b
PARAMETER num_ctx 16384
PARAMETER num_batch 128
PARAMETER num_predict 2048
PARAMETER temperature 0.7
SYSTEM 你是一个有用的AI助手，提供清晰准确的回答。支持长文本对话和复杂任务。
EOF
                ollama create gemma3-optimized -f optimized.modelfile
                ollama create gemma3-optimized-large -f optimized.modelfile
                log "✅ Models created successfully"
            fi
            break
        fi
        log "Waiting for Ollama to start... (attempt $i/30)"
        sleep 5
    done
}

# 检查 RAGFlow Docker 容器
check_ragflow_containers() {
    cd "$RAGFLOW_HOME/docker"
    
    # 检查必要的容器是否运行
    containers=("ragflow-mysql" "ragflow-redis" "ragflow-minio" "ragflow-es-01")
    
    for container in "${containers[@]}"; do
        if docker ps | grep -q "$container"; then
            log "✅ Container $container is running"
        else
            log "⚠️ Container $container is not running, starting all containers..."
            docker compose up -d
            sleep 30
            break
        fi
    done
}

# 启动 RAGFlow Python 服务
start_ragflow_server() {
    # 检查是否已经在运行
    if pgrep -f "ragflow_server.py" > /dev/null; then
        log "✅ RAGFlow server is already running"
    else
        log "Starting RAGFlow server..."
        cd "$RAGFLOW_HOME"
        
        # 设置环境变量
        export PYTHONPATH="$RAGFLOW_HOME"
        export CUDA_VISIBLE_DEVICES=""  # RTX 5090兼容性
        
        # 启动服务
        nohup .venv/bin/python api/ragflow_server.py > /var/log/ragflow-server.log 2>&1 &
        
        # 等待服务启动
        sleep 10
        
        # 验证服务
        for i in {1..30}; do
            if curl -s http://localhost:9380 &>/dev/null; then
                log "✅ RAGFlow server started successfully"
                break
            fi
            log "Waiting for RAGFlow server... (attempt $i/30)"
            sleep 5
        done
    fi
}

# 主函数
main() {
    log "========================================="
    log "Starting RAGFlow Production Environment"
    log "========================================="
    
    check_docker
    check_ollama
    check_ragflow_containers
    start_ragflow_server
    
    log "========================================="
    log "RAGFlow startup check completed"
    log "Web interface: http://localhost:9380"
    log "========================================="
}

main