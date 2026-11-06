"""
mitmproxy 广告拦截脚本（方案 C 核心组件）

功能：
1. 读取 rules/ 目录下的域名黑名单与 URL 关键词规则
2. 对匹配的 HTTP/HTTPS 请求直接返回空响应（204 No Content）或 403
3. 记录被拦截的请求到日志，便于分析与调优规则
4. 重点针对"红果短剧"等国内 App 的广告域名

使用：
    mitmdump -s block_ads.py

环境变量：
    BLOCKLIST_DIR  规则文件目录，默认 /home/mitmproxy/rules
    BLOCK_LOG      拦截日志路径，默认 /home/mitmproxy/.mitmproxy/blocked.log
"""

import os
import re
import time
from pathlib import Path
from mitmproxy import http, ctx

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
BLOCKLIST_DIR = Path(os.environ.get("BLOCKLIST_DIR", "/home/mitmproxy/rules"))
BLOCK_LOG = Path(os.environ.get("BLOCK_LOG", "/home/mitmproxy/.mitmproxy/blocked.log"))

# 内置兜底黑名单（规则文件加载失败时使用）
# ⚠️ 只放确认的广告域名，不放核心 API 域名（如 api.snssdk.com），否则 App 无法用
FALLBACK_DOMAINS = {
    # 字节跳动广告 SDK / 红果短剧广告域名
    "ad.toutiao.com",
    "ad-sdk.snssdk.com",
    "api-access.skq-one.com",
    "log.snssdk.com",
    # 通用广告联盟
    "adservice.google.com",
    "doubleclick.net",
    "googlesyndication.com",
    "googleads.g.doubleclick.net",
    "umeng.com",
    "umengcloud.com",
    "cnzz.com",
    "talkingdata.com",
}

# 需要在响应阶段替换/清空的内容类型（针对已缓存的广告资源）
AD_CONTENT_TYPES = {"image", "video"}

# ---------------------------------------------------------------------------
# 规则加载
# ---------------------------------------------------------------------------
domain_blocklist: set[str] = set()
url_keywords: list[str] = []          # URL 中包含这些关键词即拦截
path_keywords: list[str] = []         # 仅匹配 path 部分
last_load_time: float = 0.0
RELOAD_INTERVAL = 60.0                # 每 60 秒重新加载一次规则


def load_rules() -> None:
    """从 rules/ 目录加载所有 .txt 规则文件"""
    global domain_blocklist, url_keywords, path_keywords, last_load_time

    domains: set[str] = set()
    urls: list[str] = []
    paths: list[str] = []

    if not BLOCKLIST_DIR.exists():
        ctx.log.warn(f"[block_ads] 规则目录不存在: {BLOCKLIST_DIR}")
        domain_blocklist = FALLBACK_DOMAINS
        return

    for rule_file in sorted(BLOCKLIST_DIR.glob("*.txt")):
        try:
            for line in rule_file.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                # 支持简单的 AdGuard/hosts 格式：||domain.com^
                if line.startswith("||") and line.endswith("^"):
                    domains.add(line[2:-1].lower())
                # URL 关键词（以 * 开头结尾或包含通配符）
                elif "*" in line:
                    urls.append(line.replace("*", ""))
                # 普通域名
                else:
                    domains.add(line.lower())
        except Exception as e:
            ctx.log.error(f"[block_ads] 读取规则文件失败 {rule_file}: {e}")

    domain_blocklist = domains if domains else FALLBACK_DOMAINS
    url_keywords = urls
    path_keywords = paths
    last_load_time = time.time()
    ctx.log.info(
        f"[block_ads] 规则已加载: 域名 {len(domain_blocklist)} 条, "
        f"URL关键词 {len(url_keywords)} 条"
    )


def maybe_reload() -> None:
    if time.time() - last_load_time > RELOAD_INTERVAL:
        load_rules()


def is_domain_blocked(host: str) -> bool:
    host = host.lower()
    # 精确匹配或子域名匹配
    if host in domain_blocklist:
        return True
    for d in domain_blocklist:
        if host.endswith("." + d):
            return True
    return False


def is_url_blocked(url: str, path: str) -> bool:
    for kw in url_keywords:
        if kw and kw in url:
            return True
    for kw in path_keywords:
        if kw and kw in path:
            return True
    return False


def log_block(flow: http.HTTPFlow, reason: str) -> None:
    try:
        BLOCK_LOG.parent.mkdir(parents=True, exist_ok=True)
        with BLOCK_LOG.open("a", encoding="utf-8") as f:
            f.write(
                f"{time.strftime('%Y-%m-%d %H:%M:%S')}\t"
                f"{reason}\t{flow.request.method}\t{flow.request.pretty_url}\n"
            )
    except Exception:
        pass


# ---------------------------------------------------------------------------
# mitmproxy 钩子
# ---------------------------------------------------------------------------
def load(_loader) -> None:
    load_rules()


def request(flow: http.HTTPFlow) -> None:
    maybe_reload()

    req = flow.request
    host = req.pretty_host
    url = req.pretty_url
    path = req.path

    # 1. 域名黑名单
    if is_domain_blocked(host):
        log_block(flow, f"DOMAIN:{host}")
        flow.response = http.Response.make(
            204,  # No Content —— 客户端认为加载成功但内容为空，不易触发重试
            b"",
            {"Content-Type": "text/plain"},
        )
        return

    # 2. URL 关键词
    if is_url_blocked(url, path):
        log_block(flow, f"URL-KEYWORD:{host}")
        flow.response = http.Response.make(204, b"", {"Content-Type": "text/plain"})
        return

    # 3. 红果短剧专属：拦截已知广告接口路径（仅匹配明确的广告 API）
    if host.endswith("snssdk.com") or host.endswith("toutiao.com"):
        ad_paths = ("/api/ad/", "/api/ads/", "/ad_feed", "/ad_info", "/getad", "/fetchad")
        for p in ad_paths:
            if p in path:
                log_block(flow, f"HONGGUO-PATH:{host}{path}")
                flow.response = http.Response.make(204, b"", {"Content-Type": "text/plain"})
                return


def response(flow: http.HTTPFlow) -> None:
    """
    响应阶段二次拦截：对于 DNS 层未拦住、且响应明显是广告的情况进行清空。
    通过响应头特征（如 Content-Length 极小、特定 Server 头）判断。
    """
    # 预留：可在此根据响应内容特征做更精细的拦截
    pass
