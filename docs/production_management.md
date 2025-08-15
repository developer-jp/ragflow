# RAGFlow 生产环境管理指南

本文档详细介绍RAGFlow生产环境的启动、监控、故障排除和维护操作。

## 目录
- [快速开始](#快速开始)
- [服务管理](#服务管�)
- [监控系统](#监控系统)
- [故障排除](#故障排除)
- [性能优化](#性能优化)
- [维护操作](#维护操作)

## 快速开始

### 启动服务
```bash
# 启动RAGFlow服务（包含API服务器和Task Executor）
./scripts/production_manager.sh start

# 查看服务状态
./scripts/production_manager.sh status
```

### 停止服务
```bash
# 停止所有服务
./scripts/production_manager.sh stop
```

### 重启服务
```bash
# 重启所有服务
./scripts/production_manager.sh restart
```

## 服务管理

### 主要组件

1. **API服务器** - 提供Web界面和API接口
2. **Task Executor** - 处理PDF解析、OCR、embedding等任务
3. **监控系统** - 自动监控和重启异常服务

### 详细状态查看

```bash
# 查看完整服务状态
./scripts/production_manager.sh status
```

输出示例：
```
🟢 RAGFlow运行状态:
📡 API服务器:
   进程ID: 3062766
   运行时间: 04:32
   内存使用: 1596.5MB
   访问地址: http://localhost:9380
   API状态: ✅ 响应正常

⚙️  Task Executor:
   Task Executor 0: PID=3063021, 内存=5933.99MB, 运行时间=04:24
      待处理任务: 20

🟢 Task Executor监控运行中

🤖 Ollama模型: gemma3-optimized:latest
```

### 服务日志

```bash
# 查看服务日志
./scripts/production_manager.sh logs

# 实时查看Task Executor日志
tail -f logs/task_executor_0.log

# 查看最新心跳状态
grep "reported heartbeat" logs/task_executor_0.log | tail -1
```

## 监控系统

### 自动监控功能

监控系统会自动检测以下异常并重启服务：

1. **进程崩溃** - Task Executor进程不存在
2. **心跳停止** - 超过5分钟无心跳日志
3. **僵死进程** - 进程存在但无响应

### 监控管理命令

```bash
# 启动监控
./scripts/production_manager.sh monitor start

# 停止监控
./scripts/production_manager.sh monitor stop

# 查看监控状态
./scripts/production_manager.sh monitor status

# 直接使用监控脚本
./scripts/monitor_task_executor.sh start
./scripts/monitor_task_executor.sh stop
./scripts/monitor_task_executor.sh status
```

### 监控日志

```bash
# 查看监控日志
tail -f logs/task_executor_monitor.log

# 查看监控历史
cat logs/task_executor_monitor.log
```

## 故障排除

### 常见问题

#### 1. PDF解析卡住

**症状**: 文档长时间显示"正在解析"状态

**诊断**:
```bash
# 检查Task Executor状态
./scripts/production_manager.sh status

# 查看任务处理日志
tail -50 logs/task_executor_0.log

# 检查队列中的任务数量
grep "pending" logs/task_executor_0.log | tail -1
```

**解决方案**:
```bash
# 重启服务
./scripts/production_manager.sh restart

# 或者只重启Task Executor
pkill -f task_executor
# 监控会自动重启
```

#### 2. Task Executor内存过高

**正常范围**: 4-8GB（包含大型AI模型）

**内存组成**:
- Alibaba-NLP embedding模型: 2-3GB
- OCR模型缓存: 1-2GB  
- PDF处理缓存: 1-2GB
- Python进程开销: 1GB+

**如果内存超过10GB**:
```bash
# 重启Task Executor
./scripts/production_manager.sh restart
```

#### 3. Alibaba-NLP模型错误

**重要配置**: Alibaba-NLP模型必须使用CPU运行

**环境变量检查**:
```bash
echo $CUDA_VISIBLE_DEVICES  # 应该为空或""
```

**如果出现GPU相关错误**:
```bash
# 确保环境变量正确设置
export CUDA_VISIBLE_DEVICES=""
./scripts/production_manager.sh restart
```

#### 4. 服务无法启动

**检查依赖服务**:
```bash
# 检查Elasticsearch
curl -s http://localhost:1200/_health

# 检查Ollama
curl -s http://localhost:11434/api/ps

# 检查Redis
docker exec ragflow-redis redis-cli -a infini_rag_flow ping

# 检查MySQL
docker exec ragflow-mysql mysql -u root -pinfini_rag_flow -e "SHOW DATABASES;"
```

### 手动诊断

```bash
# 查看所有相关进程
ps aux | grep -E "(ragflow|task_executor)" | grep -v grep

# 查看端口占用
netstat -tulnp | grep -E "(9380|6379|1200|3306)"

# 查看Docker容器状态
docker ps | grep ragflow

# 查看系统资源
free -h
df -h
top -p $(pgrep -f ragflow)
```

## 性能优化

### 内存优化

```bash
# 监控内存使用
watch -n 5 'ps aux | grep -E "(ragflow|task_executor)" | grep -v grep'

# 清理系统缓存（谨慎使用）
sudo sync
sudo echo 3 | sudo tee /proc/sys/vm/drop_caches
```

### 任务处理优化

```bash
# 查看任务队列深度
grep "pending" logs/task_executor_0.log | tail -5

# 检查失败任务
grep "failed" logs/task_executor_0.log | tail -10

# 重置卡住的任务（需要数据库访问）
docker exec ragflow-mysql mysql -u root -pinfini_rag_flow rag_flow -e "UPDATE document SET progress = 0, progress_msg = NULL WHERE progress < 1.0 AND progress > 0;"
```

### 数据库状态检查

```bash
# 查看文档解析状态分布
docker exec ragflow-mysql mysql -u root -pinfini_rag_flow rag_flow -e "SELECT COUNT(*) as total, CASE WHEN progress < 1.0 THEN 'unfinished' ELSE 'finished' END as status FROM document GROUP BY status;"

# 查看未完成的文档
docker exec ragflow-mysql mysql -u root -pinfini_rag_flow rag_flow -e "SELECT COUNT(*) as unfinished FROM document WHERE progress < 1.0;"

# 查看最近的文档
docker exec ragflow-mysql mysql -u root -pinfini_rag_flow rag_flow -e "SELECT name, progress, progress_msg FROM document WHERE progress < 1.0 ORDER BY update_time DESC LIMIT 5;"
```

## 维护操作

### 日志清理

```bash
# 清理旧日志（保留最近7天）
find logs/ -name "*.log" -mtime +7 -delete

# 轮转日志文件
mv logs/task_executor_0.log logs/task_executor_0.log.$(date +%Y%m%d)
touch logs/task_executor_0.log
```

### 备份操作

```bash
# 备份配置文件
tar -czf ragflow_config_$(date +%Y%m%d).tar.gz \
    scripts/ docker/.env api/settings.py

# 备份数据库
docker exec ragflow-mysql mysqldump -u root -pinfini_rag_flow rag_flow > \
    ragflow_db_backup_$(date +%Y%m%d).sql
```

### 系统健康检查

```bash
# 创建健康检查脚本
cat > health_check.sh << 'EOF'
#!/bin/bash
echo "=== RAGFlow健康检查 ==="
echo "时间: $(date)"
echo ""

# 检查服务状态
./scripts/production_manager.sh status

echo ""
echo "=== 资源使用 ==="
echo "内存使用:"
free -h | head -2

echo ""
echo "磁盘使用:"
df -h | grep -E "(/$|/data)"

echo ""
echo "=== 最近错误 ==="
echo "Task Executor错误:"
grep -i error logs/task_executor_0.log | tail -3 || echo "无错误"

echo ""
echo "=== 任务统计 ==="
echo "最新心跳:"
grep "reported heartbeat" logs/task_executor_0.log | tail -1 | \
    grep -o '"pending": [0-9]*\|"done": [0-9]*\|"failed": [0-9]*' || echo "无心跳数据"
EOF

chmod +x health_check.sh
```

### 性能监控

```bash
# 创建性能监控脚本
cat > performance_monitor.sh << 'EOF'
#!/bin/bash
while true; do
    echo "$(date): CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}'), RAM=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}'), Task_Executor_RAM=$(ps -o rss= -p $(pgrep -f task_executor) | awk '{print $1/1024 "MB"}' 2>/dev/null || echo "N/A")"
    sleep 60
done > performance.log 2>&1 &
EOF

chmod +x performance_monitor.sh
```

## 重要提醒

### ⚠️ 关键配置

1. **Alibaba-NLP必须使用CPU**: `CUDA_VISIBLE_DEVICES=""`
2. **Task Executor内存使用4-8GB是正常的**
3. **监控系统会自动重启异常服务**
4. **不要手动终止monitor_task_executor进程**

### 🔧 维护建议

1. **定期检查**: 每天运行一次健康检查
2. **日志轮转**: 每周清理旧日志文件
3. **监控告警**: 关注内存使用超过10GB的情况
4. **备份数据**: 定期备份数据库和配置文件

### 📞 获取帮助

如果遇到问题：

1. 查看此文档的故障排除章节
2. 检查日志文件中的错误信息
3. 运行健康检查脚本获取系统状态
4. 记录问题发生的时间和具体症状

---

**文档版本**: 1.0  
**最后更新**: 2025-08-15  
**适用版本**: RAGFlow v0.19.1+