#!/usr/bin/env bash
# =============================================================================
# init.sh —— 环境初始化与前置检查
# 用法: ./scripts/init.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "========================================"
echo " AdGuardHome + mitmproxy 初始化检查"
echo "========================================"

# 1. Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "[错误] 未检测到 docker，请先安装 Docker Desktop"
    echo "       下载地址: https://www.docker.com/products/docker-desktop"
    exit 1
fi

# 2. Docker daemon
if ! docker info >/dev/null 2>&1; then
    echo "[错误] Docker daemon 未运行，请先启动 Docker Desktop"
    exit 1
fi
echo "[OK] Docker 已就绪"

# 3. docker compose
if ! docker compose version >/dev/null 2>&1; then
    echo "[错误] 未检测到 docker compose 插件"
    exit 1
fi
echo "[OK] docker compose 已就绪"

# 4. 检查端口 8053 占用（AdGuardHome DNS）
echo ""
echo "[检查] 端口 8053 (AdGuardHome DNS) 占用情况..."
if lsof -nP -iUDP:8053 >/dev/null 2>&1 || lsof -nP -iTCP:8053 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[警告] 端口 8053 已被占用，请在 docker-compose.yml 中修改。"
    lsof -nP -iUDP:8053 2>/dev/null | head -5 || true
else
    echo "[OK] 端口 8053 空闲"
fi

# 5. 提示 pf 端口转发方案
echo ""
echo "[提示] 本方案保留 mDNSResponder（53 端口），不破坏 Bonjour/AirDrop。"
echo "       AdGuardHome 运行在 8053，通过 pf 将局域网 53 端口转发到 8053。"
echo "       启动容器后执行: ./scripts/pf-enable.sh"

# 6. 创建持久化目录
mkdir -p adguard/conf adguard/work mitmproxy/certs
echo "[OK] 持久化目录已就绪"

# 7. 设置权限（mitmproxy 容器内用户为 mitmproxy，UID 1000）
chmod -R 755 mitmproxy/scripts mitmproxy/rules
echo "[OK] 脚本与规则目录权限已设置"

echo ""
echo "========================================"
echo " 初始化完成！下一步："
echo "   ./scripts/start.sh    启动服务"
echo "========================================"
