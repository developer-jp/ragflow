#!/usr/bin/env python3
"""
RAGFlow 生产环境启动脚本 - 简化版本
直接使用Flask，但配置为生产参数
"""
import os
import sys
import logging
from logging.handlers import RotatingFileHandler

# 添加项目路径
sys.path.insert(0, '/data/ragflow-deployment/ragflow')

# 设置环境变量
os.environ.setdefault("PYTHONPATH", "/data/ragflow-deployment/ragflow")
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")  # RTX 5090兼容性
os.environ.setdefault("FLASK_ENV", "production")
os.environ.setdefault("FLASK_DEBUG", "0")

# 配置日志
log_dir = "/data/ragflow-deployment/ragflow/logs"
os.makedirs(log_dir, exist_ok=True)

# 设置更详细的日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(name)s: %(message)s',
    handlers=[
        RotatingFileHandler(
            os.path.join(log_dir, 'ragflow_production.log'),
            maxBytes=100*1024*1024,  # 100MB
            backupCount=5
        ),
        logging.StreamHandler()
    ]
)

def main():
    """启动生产环境RAGFlow"""
    try:
        # 导入应用
        from api.ragflow_server import app
        
        # 生产环境配置
        app.config.update(
            DEBUG=False,
            TESTING=False,
            SECRET_KEY=os.environ.get('SECRET_KEY', os.urandom(24)),
            MAX_CONTENT_LENGTH=128 * 1024 * 1024,  # 128MB
            SEND_FILE_MAX_AGE_DEFAULT=31536000,  # 1年缓存
        )
        
        # 启动服务器
        print("🚀 启动RAGFlow生产服务器...")
        print(f"📍 访问地址: http://localhost:9380")
        print(f"📝 日志目录: {log_dir}")
        
        app.run(
            host='0.0.0.0',
            port=9380,
            debug=False,
            threaded=True,
            use_reloader=False,
            processes=1
        )
        
    except Exception as e:
        logging.error(f"RAGFlow启动失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()