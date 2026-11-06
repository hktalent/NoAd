#!/usr/bin/env bash
# =============================================================================
# status.sh - 查看服务运行状态与端口占用
# 用法: ./scripts/status.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "========================================"
echo " 容器状态"
echo "========================================"
docker compose ps

echo ""
echo "========================================"
echo " 关键端口监听"
echo "========================================"
for port in 8053 3001 8082 8081; do
    if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1 || \
       lsof -nP -iUDP:$port >/dev/null 2>&1; then
        echo "  [监听中] 端口 $port"
    else
        echo "  [未监听] 端口 $port"
    fi
done

echo ""
echo "========================================"
echo " mitmproxy 拦截日志（最近 20 条）"
echo "========================================"
BLOCKED_LOG="$PROJECT_DIR/mitmproxy/certs/blocked.log"
if [[ -f "$BLOCKED_LOG" ]]; then
    tail -20 "$BLOCKED_LOG"
else
    echo "  暂无拦截记录（日志文件: ${BLOCKED_LOG}）"
fi
