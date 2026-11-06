#!/usr/bin/env bash
# =============================================================================
# start.sh —— 启动 AdGuardHome + mitmproxy
# 用法: ./scripts/start.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "[启动] docker compose up -d ..."
docker compose up -d

echo ""
echo "等待服务就绪..."
sleep 3

echo ""
echo "========================================"
echo " 服务已启动"
echo "========================================"
echo " AdGuardHome Web UI : http://localhost:3001"
echo " mitmproxy 代理端口 : http://localhost:8082"
echo " mitmproxy Web UI   : http://localhost:8081"
echo ""
echo " 查看日志: docker compose logs -f"
echo " 查看状态: ./scripts/status.sh"
echo "========================================"
