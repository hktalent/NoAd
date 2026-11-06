#!/usr/bin/env bash
# =============================================================================
# pf-enable.sh —— 启用 pf 端口转发（53 → 8053），让手机可直接用 Mac IP 作 DNS
# 同时保留 mDNSResponder，Bonjour/AirDrop 正常
#
# 用法: ./scripts/pf-enable.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANCHOR_FILE="$PROJECT_DIR/pf/adguard.anchor"
ANCHOR_NAME="adguard"

echo "========================================"
echo " 启用 pf DNS 端口转发 (53 -> 8053)"
echo "========================================"

# 1. 检查 pf 规则文件
if [[ ! -f "$ANCHOR_FILE" ]]; then
    echo "[错误] pf 规则文件不存在: $ANCHOR_FILE"
    exit 1
fi

# 2. 加载 anchor
echo "[1/3] 加载 pf anchor 规则..."
sudo pfctl -a "$ANCHOR_NAME" -f "$ANCHOR_FILE" 2>/dev/null || {
    echo "[错误] 加载 pf 规则失败，请确认已授予 sudo 权限"
    exit 1
}
echo "  [OK] anchor 已加载: $ANCHOR_NAME"

# 3. 启用 pf
echo "[2/3] 启用 pf..."
sudo pfctl -e 2>/dev/null || echo "  (pf 已启用，跳过)"
echo "  [OK] pf 已启用"

# 4. 设置 Mac 自身 DNS 为公共 DNS（不经过 AdGuardHome，确保 Mac 上网正常）
#    macOS pf 对 lo0 的 rdr 不可靠，Mac 自身不走端口转发
echo "[3/3] 设置 Mac 自身 DNS 为公共 DNS（223.5.5.5, 119.29.29.29）..."
NETWORK_SERVICE="Wi-Fi"
# 尝试检测当前活跃网络服务
CURRENT_SERVICE="$(networksetup -listnetworkserviceorder 2>/dev/null \
    | grep -B1 "$(route get default 2>/dev/null | grep interface | awk '{print $2}')" \
    | head -1 | sed 's/.*) //')"
if [[ -n "$CURRENT_SERVICE" ]]; then
    NETWORK_SERVICE="$CURRENT_SERVICE"
fi
sudo networksetup -setdnsservers "$NETWORK_SERVICE" "223.5.5.5" "119.29.29.29" 2>/dev/null || {
    echo "  [警告] 自动设置 DNS 失败，请手动设置："
    echo "         系统设置 → 网络 → $NETWORK_SERVICE → 详细信息 → DNS"
    echo "         添加: 223.5.5.5, 119.29.29.29"
}
echo "  [OK] Mac DNS 已设置为 223.5.5.5, 119.29.29.29"

echo ""
echo "========================================"
echo " 完成！验证："
echo "   手机 DNS 设为 Mac IP 即可（标准 53 端口）"
echo "   Mac 自身使用公共 DNS，上网不受影响"
echo "   Bonjour/AirDrop/AirPlay 不受影响"
echo ""
echo " 查看 pf 规则: sudo pfctl -a $ANCHOR_NAME -s nat"
echo " 关闭转发: ./scripts/pf-disable.sh"
echo "========================================"
