#!/usr/bin/env python3
"""
RAGFlow 生产环境启动脚本
使用 Gunicorn 作为 WSGI 服务器
"""

import multiprocessing
import os

# 设置环境变量
os.environ.setdefault("PYTHONPATH", "/data/ragflow-deployment/ragflow")
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")  # RTX 5090兼容性

# Gunicorn 配置
bind = "0.0.0.0:9380"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "gevent"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 120
keepalive = 5

# 日志配置
accesslog = "/data/ragflow-deployment/ragflow/logs/access.log"
errorlog = "/data/ragflow-deployment/ragflow/logs/error.log"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# 进程配置
daemon = True
pidfile = "/data/ragflow-deployment/ragflow/ragflow.pid"
user = "sns"
group = "sns"

# 应用配置
wsgi_file = "/data/ragflow-deployment/ragflow/api/ragflow_server.py"

# 预加载应用
preload_app = True

# 工作进程重启
worker_tmp_dir = "/dev/shm"

def post_fork(server, worker):
    """工作进程启动后的钩子"""
    server.log.info("Worker spawned (pid: %s)", worker.pid)

def when_ready(server):
    """服务器准备就绪时的钩子"""
    server.log.info("RAGFlow production server is ready. Listening on: %s", bind)

def on_exit(server):
    """服务器退出时的钩子"""
    server.log.info("RAGFlow production server shutting down.")

# 监控配置
statsd_host = None  # 可配置为 "localhost:8125"
proc_name = "ragflow-production"