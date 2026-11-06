#!/usr/bin/env bash
# =============================================================================
# export-cert.sh —— 导出 mitmproxy 根证书到 certs-export/ 目录，方便安装到设备
# 用法: ./scripts/export-cert.sh
#
# mitmproxy 首次启动会在 ~/.mitmproxy（即挂载的 mitmproxy/certs/）下生成根证书。
# 本脚本将其复制到 certs-export/ 并转换为各种格式，供 iOS/Android/macOS 安装。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CERT_SRC_DIR="$PROJECT_DIR/mitmproxy/certs"
EXPORT_DIR="$PROJECT_DIR/certs-export"

echo "========================================"
echo " 导出 mitmproxy 根证书"
echo "========================================"

# 等待证书生成
echo "[等待] 检查 mitmproxy 根证书..."
for i in {1..30}; do
    if [[ -f "$CERT_SRC_DIR/mitmproxy-ca-cert.pem" ]]; then
        echo "[OK] 找到根证书: $CERT_SRC_DIR/mitmproxy-ca-cert.pem"
        break
    fi
    echo "  等待中... ($i/30) 请确保 mitmproxy 容器已启动"
    sleep 2
done

if [[ ! -f "$CERT_SRC_DIR/mitmproxy-ca-cert.pem" ]]; then
    echo "[错误] 未找到 mitmproxy 根证书。请先运行 ./scripts/start.sh 启动服务。"
    exit 1
fi

mkdir -p "$EXPORT_DIR"

# PEM 格式（通用）
cp "$CERT_SRC_DIR/mitmproxy-ca-cert.pem" "$EXPORT_DIR/mitmproxy-ca-cert.pem"
echo "[OK] PEM 格式 -> $EXPORT_DIR/mitmproxy-ca-cert.pem"

# DER / CER 格式（Android 系统证书安装常用）
if command -v openssl >/dev/null 2>&1; then
    openssl x509 -in "$CERT_SRC_DIR/mitmproxy-ca-cert.pem" \
        -outform DER -out "$EXPORT_DIR/mitmproxy-ca-cert.cer"
    echo "[OK] DER/CER 格式 -> $EXPORT_DIR/mitmproxy-ca-cert.cer"
fi

# P12 / PKCS12 格式（iOS 部分场景）
if [[ -f "$CERT_SRC_DIR/mitmproxy-ca.pem" ]] && command -v openssl >/dev/null 2>&1; then
    openssl pkcs12 -export \
        -in "$CERT_SRC_DIR/mitmproxy-ca.pem" \
        -inkey "$CERT_SRC_DIR/mitmproxy-ca.pem" \
        -out "$EXPORT_DIR/mitmproxy-ca-cert.p12" \
        -passout pass: 2>/dev/null || true
    [[ -f "$EXPORT_DIR/mitmproxy-ca-cert.p12" ]] && \
        echo "[OK] PKCS12 格式 -> $EXPORT_DIR/mitmproxy-ca-cert.p12"
fi

echo ""
echo "========================================"
echo " 证书已导出到: $EXPORT_DIR"
echo "========================================"
ls -lh "$EXPORT_DIR"
echo ""
echo "安装说明（详见 README.md）："
echo "  macOS : 双击 .pem -> 钥匙串访问 -> 设为始终信任"
echo "  iOS   : AirDrop 发送 .pem -> 设置 -> 通用 -> VPN与设备管理 -> 安装"
echo "  Android: 安装 .cer -> 设置 -> 安全 -> 加密与凭据 -> 安装证书"
echo "========================================"
