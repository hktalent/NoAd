#!/usr/bin/env bash
# =============================================================================
# stop.sh —— 停止服务
# 用法: ./scripts/stop.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "[停止] docker compose down ..."
docker compose down

echo "[完成] 服务已停止"
