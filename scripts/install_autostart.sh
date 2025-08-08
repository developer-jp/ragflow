#!/bin/bash
# RAGFlow 自动启动服务安装脚本

set -e

echo "========================================="
echo "RAGFlow 开机自启动配置"
echo "========================================="

# 创建新的 systemd 服务文件
sudo tee /etc/systemd/system/ragflow-production.service << 'EOF'
[Unit]
Description=RAGFlow Production Service with Ollama
Requires=docker.service
After=docker.service ollama.service network-online.target
Wants=network-online.target ollama.service

[Service]
Type=forking
RemainAfterExit=yes
WorkingDirectory=/data/ragflow-deployment/ragflow
ExecStartPre=/bin/sleep 10
ExecStart=/data/ragflow-deployment/ragflow/scripts/startup_check.sh
ExecStop=/data/ragflow-deployment/ragflow/scripts/production_manager.sh stop
TimeoutStartSec=300
TimeoutStopSec=60
Restart=on-failure
RestartSec=30
User=sns
Group=sns
Environment="HOME=/home/sns"
Environment="PYTHONPATH=/data/ragflow-deployment/ragflow"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 更新 Ollama 服务配置
sudo tee /etc/systemd/system/ollama.service << 'EOF'
[Unit]
Description=Ollama LLM Service
After=network-online.target
Before=ragflow-production.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3
User=root
Group=root
Environment="HOME=/root"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/data/models/ollama"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_MAX_LOADED_MODELS=1" 
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_GPU_OVERHEAD=2048"
Environment="OLLAMA_MAX_QUEUE=512"
Environment="OLLAMA_LOAD_TIMEOUT=10m"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 禁用旧的 ragflow.service
echo "禁用旧的 ragflow.service..."
sudo systemctl disable ragflow.service 2>/dev/null || true
sudo systemctl stop ragflow.service 2>/dev/null || true

# 重新加载 systemd 配置
echo "重新加载 systemd 配置..."
sudo systemctl daemon-reload

# 启用新服务
echo "启用开机自启动服务..."
sudo systemctl enable ollama.service
sudo systemctl enable ragflow-production.service
sudo systemctl enable docker.service

# 显示服务状态
echo ""
echo "========================================="
echo "服务配置完成！"
echo "========================================="
echo ""
echo "已启用的服务："
systemctl list-unit-files | grep -E "ragflow-production|ollama|docker" | grep enabled

echo ""
echo "使用以下命令管理服务："
echo "  启动服务: sudo systemctl start ragflow-production"
echo "  停止服务: sudo systemctl stop ragflow-production"
echo "  查看状态: sudo systemctl status ragflow-production"
echo "  查看日志: sudo journalctl -u ragflow-production -f"
echo ""
echo "系统将在下次启动时自动运行 RAGFlow 和 Ollama"