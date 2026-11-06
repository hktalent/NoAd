#!/usr/bin/env bash
# =============================================================================
# pf-disable.sh —— 关闭 pf DNS 端口转发，恢复系统 DNS
# 用法: ./scripts/pf-disable.sh
# =============================================================================
set -euo pipefail

ANCHOR_NAME="adguard"

echo "========================================"
echo " 关闭 pf DNS 端口转发"
echo "========================================"

# 1. 移除 anchor 规则
echo "[1/2] 移除 pf anchor 规则..."
sudo pfctl -a "$ANCHOR_NAME" -F all 2>/dev/null || true
echo "  [OK] anchor 已移除"

# 2. 恢复 Mac 系统 DNS 为 DHCP 自动获取
echo "[2/2] 恢复 Mac 系统 DNS 为自动获取..."
NETWORK_SERVICE="Wi-Fi"
CURRENT_SERVICE="$(networksetup -listnetworkserviceorder 2>/dev/null \
    | grep -B1 "$(route get default 2>/dev/null | grep interface | awk '{print $2}')" \
    | head -1 | sed 's/.*) //')"
if [[ -n "$CURRENT_SERVICE" ]]; then
    NETWORK_SERVICE="$CURRENT_SERVICE"
fi
sudo networksetup -setdnsservers "$NETWORK_SERVICE" Empty 2>/dev/null || true
echo "  [OK] DNS 已恢复为自动获取"

echo ""
echo "========================================"
echo " 已关闭端口转发，DNS 恢复正常"
echo "========================================"
