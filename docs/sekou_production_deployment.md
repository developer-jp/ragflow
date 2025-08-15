# RAGFlow 生产环境部署文档 v1.0

## 📋 概述

本文档提供完整的 RAGFlow + Ollama 生产环境部署指南，包含开机自启动配置。适用于 toB 客户的本地化部署需求。

## 🛠️ 系统要求

### 硬件配置（推荐）
- **CPU**: 16 核心以上 (Intel Xeon 或 AMD EPYC)
- **内存**: 64GB RAM 以上
- **GPU**: NVIDIA RTX 4090/5090 或 A100 (32GB+ VRAM)
- **存储**: 2TB+ SSD (NVMe 推荐)
- **网络**: 千兆以太网

### 软件环境
- **操作系统**: Ubuntu 20.04/22.04 LTS 或 CentOS 8+
- **Docker**: 24.0+ 
- **Docker Compose**: 2.20+
- **NVIDIA Driver**: 525.85+
- **CUDA**: 12.0+

## 🚀 快速部署指南

### 步骤 1: 系统初始化

```bash
#!/bin/bash
# 系统更新和依赖安装
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git vim htop

# Docker 安装
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Docker Compose 安装  
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# NVIDIA Container Toolkit 安装
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### 步骤 2: Ollama 安装和配置

```bash
# Ollama 安装
curl -fsSL https://ollama.ai/install.sh | sh

# 下载并优化模型
ollama pull gemma3:27b

# 创建优化模型配置
cat > /tmp/optimized.modelfile << 'EOF'
FROM gemma3:27b
PARAMETER num_ctx 16384
PARAMETER num_batch 128
PARAMETER num_predict 2048
PARAMETER temperature 0.7
PARAMETER top_k 40
PARAMETER top_p 0.9
PARAMETER repeat_penalty 1.1
SYSTEM 你是一个有用的AI助手，提供清晰准确的回答。支持长文本对话和复杂任务。
EOF

ollama create gemma3-optimized -f /tmp/optimized.modelfile
ollama create gemma3-optimized-large -f /tmp/optimized.modelfile

# 验证模型
ollama list
```

### 步骤 3: RAGFlow 部署

```bash
# 创建部署目录
sudo mkdir -p /opt/ragflow-production
cd /opt/ragflow-production

# 克隆项目 (或使用发布包)
git clone https://github.com/infiniflow/ragflow.git
cd ragflow

# 复制并配置环境文件
cp docker/.env.template docker/.env.production

# 编辑配置文件
cat > docker/.env.production << 'EOF'
# RAGFlow 生产环境配置
COMPOSE_PROJECT_NAME=ragflow
RAGFLOW_VERSION=v0.14.0
TIMEZONE=Asia/Shanghai

# MySQL 配置
MYSQL_PASSWORD=infini_rag_flow
MYSQL_ROOT_PASSWORD=infini_rag_flow

# Redis 配置  
REDIS_PASSWORD=infiniflow

# API 配置
SECRET_KEY=ragflow-production-secret-key-2024

# 服务端口
SVR_HTTP_PORT=9380

# GPU 配置
CUDA_VISIBLE_DEVICES=0

# 存储配置
DOCKER_VOLUME_DIRECTORY=./volumes
EOF

# 创建数据目录
sudo mkdir -p ./volumes/{mysql,redis,minio,elasticsearch}
sudo chown -R 1001:1001 ./volumes/elasticsearch
```

### 步骤 4: 数据库和配置初始化

```bash
# 启动基础服务
docker-compose -f docker/docker-compose.production.yml up -d mysql redis minio elasticsearch

# 等待服务启动
sleep 30

# 初始化 RAGFlow 服务
docker-compose -f docker/docker-compose.production.yml up -d ragflow

# 等待初始化完成
sleep 60
```

## 🔧 生产环境优化配置

### 步骤 5: Nginx 反向代理配置

```bash
# 安装 Nginx
sudo apt install -y nginx

# 创建 RAGFlow 配置
sudo cat > /etc/nginx/sites-available/ragflow << 'EOF'
server {
    listen 80;
    server_name your-domain.com;  # 替换为实际域名
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://127.0.0.1:9380;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时配置
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# 启用配置
sudo ln -s /etc/nginx/sites-available/ragflow /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 步骤 6: SSL/HTTPS 配置 (可选)

```bash
# 安装 Certbot
sudo apt install -y certbot python3-certbot-nginx

# 申请 SSL 证书
sudo certbot --nginx -d your-domain.com

# 自动续期
echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
```

## 🏁 开机自启动配置

### 方案 1: Systemd 服务配置

```bash
# 创建 Ollama 服务
sudo cat > /etc/systemd/system/ollama.service << 'EOF'
[Unit]
Description=Ollama Service
After=network.target
Wants=network.target

[Service]
Type=notify
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
Environment=OLLAMA_HOST=0.0.0.0:11434
Environment=OLLAMA_MODELS=/var/lib/ollama/models
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 创建 RAGFlow 服务
sudo cat > /etc/systemd/system/ragflow.service << 'EOF'
[Unit]
Description=RAGFlow Production Service
Requires=docker.service ollama.service
After=docker.service ollama.service
BindsTo=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/ragflow-production/ragflow
ExecStart=/usr/local/bin/docker-compose -f docker/docker-compose.production.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker/docker-compose.production.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable ollama.service
sudo systemctl enable ragflow.service
sudo systemctl enable nginx.service

# 启动服务验证
sudo systemctl start ollama.service
sudo systemctl start ragflow.service
```

### 方案 2: 启动脚本配置

```bash
# 创建启动脚本
sudo cat > /opt/ragflow-production/start-all.sh << 'EOF'
#!/bin/bash

# RAGFlow 生产环境启动脚本
set -e

LOG_FILE="/var/log/ragflow-startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date): Starting RAGFlow Production Environment..."

# 检查 Docker 服务
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..."
    systemctl start docker
    sleep 10
fi

# 启动 Ollama
echo "Starting Ollama service..."
if ! pgrep -x "ollama" > /dev/null; then
    systemctl start ollama
    sleep 20
fi

# 验证模型可用性
echo "Checking Ollama models..."
while ! ollama list | grep -q "gemma3-optimized"; do
    echo "Waiting for Ollama models to be ready..."
    sleep 10
done

# 启动 RAGFlow 服务
cd /opt/ragflow-production/ragflow
echo "Starting RAGFlow services..."
docker-compose -f docker/docker-compose.production.yml up -d

# 等待服务就绪
echo "Waiting for services to be ready..."
sleep 60

# 健康检查
echo "Performing health check..."
for i in {1..30}; do
    if curl -f http://localhost:9380/health &>/dev/null; then
        echo "✅ RAGFlow is ready!"
        break
    fi
    echo "Waiting for RAGFlow... (attempt $i/30)"
    sleep 10
done

# 启动 Nginx
systemctl start nginx

echo "$(date): RAGFlow Production Environment startup completed!"
EOF

chmod +x /opt/ragflow-production/start-all.sh

# 添加到 crontab 开机启动
(crontab -l 2>/dev/null; echo "@reboot sleep 30 && /opt/ragflow-production/start-all.sh") | crontab -
```

## 📊 监控和日志配置

### 系统监控脚本

```bash
# 创建监控脚本
sudo cat > /opt/ragflow-production/monitor.sh << 'EOF'
#!/bin/bash

# RAGFlow 服务监控脚本
LOG_FILE="/var/log/ragflow-monitor.log"

check_service() {
    local service_name=$1
    local check_command=$2
    
    if eval "$check_command" &>/dev/null; then
        echo "$(date): ✅ $service_name is healthy"
    else
        echo "$(date): ❌ $service_name is down, attempting restart..."
        # 这里添加重启逻辑
        /opt/ragflow-production/start-all.sh
    fi
}

# 检查各服务状态
check_service "Docker" "docker ps"
check_service "Ollama" "curl -s http://localhost:11434/api/tags"
check_service "RAGFlow" "curl -s http://localhost:9380"
check_service "MySQL" "docker exec ragflow-mysql mysqladmin ping"
check_service "Redis" "docker exec ragflow-redis redis-cli ping"
EOF

chmod +x /opt/ragflow-production/monitor.sh

# 添加到 crontab (每5分钟检查一次)
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/ragflow-production/monitor.sh >> /var/log/ragflow-monitor.log 2>&1") | crontab -
```

### 日志轮转配置

```bash
# 配置日志轮转
sudo cat > /etc/logrotate.d/ragflow << 'EOF'
/var/log/ragflow-*.log {
    daily
    missingok
    rotate 30
    compress
    notifempty
    create 0644 root root
    postrotate
        /bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
```

## 🔒 安全加固配置

### 防火墙配置

```bash
# UFW 防火墙配置
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 允许必要端口
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 限制内部端口访问 (仅允许本地)
sudo ufw allow from 127.0.0.1 to any port 9380
sudo ufw allow from 127.0.0.1 to any port 11434

# 应用配置
sudo ufw reload
```

### 数据库安全

```bash
# 创建数据库备份脚本
sudo cat > /opt/ragflow-production/backup-db.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/ragflow-production/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# MySQL 备份
docker exec ragflow-mysql mysqldump -u root -pinfini_rag_flow rag_flow > "$BACKUP_DIR/ragflow_$DATE.sql"

# 压缩备份
gzip "$BACKUP_DIR/ragflow_$DATE.sql"

# 删除7天前的备份
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete

echo "$(date): Database backup completed: ragflow_$DATE.sql.gz"
EOF

chmod +x /opt/ragflow-production/backup-db.sh

# 每日凌晨2点自动备份
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/ragflow-production/backup-db.sh >> /var/log/ragflow-backup.log 2>&1") | crontab -
```

## ✅ 部署验证清单

### 基础服务检查

```bash
# 创建验证脚本
cat > /opt/ragflow-production/verify-deployment.sh << 'EOF'
#!/bin/bash

echo "🔍 RAGFlow 生产环境部署验证"
echo "================================"

# 检查 Docker
if docker --version &>/dev/null; then
    echo "✅ Docker: $(docker --version)"
else
    echo "❌ Docker 未安装或不可用"
    exit 1
fi

# 检查 Ollama
if ollama --version &>/dev/null; then
    echo "✅ Ollama: $(ollama --version)"
    echo "   模型列表:"
    ollama list | grep gemma3 | sed 's/^/   /'
else
    echo "❌ Ollama 未安装或不可用"
    exit 1
fi

# 检查 RAGFlow 服务
if curl -s http://localhost:9380 &>/dev/null; then
    echo "✅ RAGFlow Web 服务正常"
else
    echo "❌ RAGFlow Web 服务不可用"
fi

# 检查数据库连接
if docker exec ragflow-mysql mysqladmin ping -u root -pinfini_rag_flow &>/dev/null; then
    echo "✅ MySQL 数据库连接正常"
else
    echo "❌ MySQL 数据库连接失败"
fi

# 检查 GPU 使用
if nvidia-smi &>/dev/null; then
    echo "✅ NVIDIA GPU 可用"
    nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader,nounits | sed 's/^/   GPU: /'
else
    echo "⚠️ 未检测到 NVIDIA GPU"
fi

# 检查端口占用
echo "📊 端口使用情况:"
ss -tlnp | grep -E ':80|:443|:9380|:11434' | sed 's/^/   /'

echo ""
echo "🎉 部署验证完成！"
EOF

chmod +x /opt/ragflow-production/verify-deployment.sh
```

## 🚀 快速启动命令

### 使用项目内置脚本

```bash
# 使用生产管理脚本
cd /opt/ragflow-production/ragflow
./scripts/production_manager.sh start

# 或者使用简单启动脚本
./scripts/start_production.sh start

# 或者使用 Python 启动脚本
python3 ./scripts/start_production_simple.py
```

### 使用系统级脚本

```bash
# 一键部署命令
curl -fsSL https://raw.githubusercontent.com/your-repo/ragflow-deploy/main/quick-deploy.sh | bash

# 或者手动执行
/opt/ragflow-production/start-all.sh
```

### 生产管理命令

```bash
# 启动服务
./scripts/production_manager.sh start

# 停止服务
./scripts/production_manager.sh stop

# 重启服务
./scripts/production_manager.sh restart

# 查看状态
./scripts/production_manager.sh status

# 查看日志
./scripts/production_manager.sh logs
```

## 📞 故障排除

### 常见问题解决

1. **Ollama 模型加载失败**
```bash
# 重新下载模型
ollama rm gemma3-optimized
ollama pull gemma3:27b
ollama create gemma3-optimized -f /tmp/optimized.modelfile
```

2. **RAGFlow 启动失败**
```bash
# 查看日志
docker-compose -f docker/docker-compose.production.yml logs ragflow

# 重启服务
docker-compose -f docker/docker-compose.production.yml restart
```

3. **数据库连接问题**
```bash
# 检查 MySQL 容器
docker logs ragflow-mysql

# 重置数据库密码
docker exec -it ragflow-mysql mysql -u root -p
```

### 性能优化建议

1. **GPU 内存优化**
   - 调整 `num_ctx` 和 `num_batch` 参数
   - 使用 `nvidia-smi` 监控 GPU 使用率

2. **数据库性能调优**
   - 调整 MySQL `innodb_buffer_pool_size`
   - 启用查询缓存

3. **网络优化**
   - 配置 Nginx 缓存
   - 启用 gzip 压缩

## 📋 维护清单

### 日常维护任务
- [ ] 检查服务运行状态
- [ ] 监控系统资源使用
- [ ] 查看错误日志
- [ ] 验证备份完整性

### 定期维护任务
- [ ] 更新 Docker 镜像
- [ ] 更新 Ollama 模型
- [ ] 清理无用文件
- [ ] 安全更新

### 应急响应计划
- [ ] 服务故障恢复流程
- [ ] 数据恢复程序
- [ ] 联系技术支持

## 📄 附录

### 目录结构
```
/opt/ragflow-production/
├── ragflow/                 # RAGFlow 主程序
│   ├── docker/             # Docker 配置文件
│   │   ├── .env.production
│   │   └── docker-compose.production.yml
│   ├── scripts/            # 脚本文件
│   │   ├── production_manager.sh
│   │   ├── start_production.sh
│   │   ├── start_production_simple.py
│   │   └── ragflow_production.py
│   └── sekou_production_deployment.md  # 本文档
├── backups/                 # 数据备份目录
├── logs/                    # 日志文件
├── start-all.sh            # 启动脚本
├── monitor.sh              # 监控脚本
├── backup-db.sh            # 备份脚本
└── verify-deployment.sh    # 验证脚本
```

### 端口使用说明
- `80/443`: Nginx Web 服务
- `9380`: RAGFlow 主服务
- `11434`: Ollama API 服务
- `5455`: MySQL 数据库
- `6379`: Redis 缓存
- `1200`: Elasticsearch

---

**版本**: v1.0  
**更新日期**: 2025-01-08  
**适用版本**: RAGFlow v0.14.0, Ollama v0.1.0+  
**支持系统**: Ubuntu 20.04+, CentOS 8+

🎯 **部署完成后，访问 http://your-server-ip 开始使用 RAGFlow！**