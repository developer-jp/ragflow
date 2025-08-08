#!/bin/bash
# 使用 crontab 配置开机自启动（备用方案）

set -e

echo "========================================="
echo "配置 crontab 开机自启动"
echo "========================================="

# 创建启动脚本
STARTUP_SCRIPT="/home/sns/ragflow_autostart.sh"

cat > "$STARTUP_SCRIPT" << 'EOF'
#!/bin/bash
# RAGFlow 开机自启动脚本

# 等待系统完全启动
sleep 30

# 设置日志
LOG_FILE="/home/sns/ragflow_startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(date)] Starting RAGFlow auto-startup..."

# 启动 Ollama（如果没有运行）
if ! pgrep -x "ollama" > /dev/null; then
    echo "Starting Ollama..."
    ollama serve &
    sleep 20
fi

# 检查 Ollama 模型
if ! ollama list | grep -q "gemma3-optimized"; then
    echo "Loading Ollama models..."
    ollama pull gemma3:27b
    
    # 创建优化模型
    cd /tmp
    cat > optimized.modelfile << 'MODEL'
FROM gemma3:27b
PARAMETER num_ctx 16384
PARAMETER num_batch 128
PARAMETER num_predict 2048
PARAMETER temperature 0.7
SYSTEM 你是一个有用的AI助手，提供清晰准确的回答。支持长文本对话和复杂任务。
MODEL
    
    ollama create gemma3-optimized -f optimized.modelfile
    ollama create gemma3-optimized-large -f optimized.modelfile
fi

# 启动 RAGFlow Docker 容器
cd /data/ragflow-deployment/ragflow/docker
docker compose up -d

# 等待容器启动
sleep 30

# 启动 RAGFlow Python 服务
cd /data/ragflow-deployment/ragflow
if ! pgrep -f "ragflow_server.py" > /dev/null; then
    export PYTHONPATH="/data/ragflow-deployment/ragflow"
    export CUDA_VISIBLE_DEVICES=""
    nohup .venv/bin/python api/ragflow_server.py > /home/sns/ragflow_server.log 2>&1 &
    echo "RAGFlow server started with PID: $!"
fi

echo "[$(date)] RAGFlow auto-startup completed!"
EOF

chmod +x "$STARTUP_SCRIPT"

# 添加到当前用户的 crontab
echo "添加 crontab 条目..."
(crontab -l 2>/dev/null | grep -v "ragflow_autostart.sh"; echo "@reboot $STARTUP_SCRIPT") | crontab -

echo ""
echo "========================================="
echo "crontab 配置完成！"
echo "========================================="
echo ""
echo "已创建启动脚本: $STARTUP_SCRIPT"
echo "已添加 crontab 条目:"
crontab -l | grep ragflow_autostart.sh
echo ""
echo "系统将在下次重启时自动执行启动脚本"
echo ""
echo "手动测试启动脚本:"
echo "  $STARTUP_SCRIPT"
echo ""
echo "查看 crontab:"
echo "  crontab -l"
echo ""
echo "查看启动日志:"
echo "  tail -f /home/sns/ragflow_startup.log"