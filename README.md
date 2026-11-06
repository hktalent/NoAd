# AdGuardHome + mitmproxy 广告过滤方案（方案 C）

> 过滤网络广告，**重点拦截"红果短剧"App 内广告**。
> 采用 **DNS 层过滤（AdGuardHome）+ HTTPS 中间人代理（mitmproxy）** 双层方案，
> 弥补纯 DNS 过滤对加密广告流量无能为力的缺陷。

---

## 一、方案架构

```
┌─────────────────────────────────────────────────────────────┐
│                        你的设备                               │
│  (手机 / 电脑)                                                │
│   ① DNS 指向 AdGuardHome (53 端口，标准端口)                  │
│   ② HTTP/HTTPS 代理指向 mitmproxy (8082 端口)                 │
└───────────────────┬─────────────────────┬───────────────────┘
                    │ DNS 查询             │ 代理请求
                    ▼                     ▼
        ┌───────────────────┐   ┌───────────────────────┐
        │   AdGuardHome     │   │      mitmproxy         │
        │  (DNS 广告过滤)    │   │  (HTTPS 中间人)         │
        │                   │   │                        │
        │ 拦截广告域名解析   │   │ 解密 HTTPS，按规则拦截  │
        │ 返回 NXDOMAIN     │   │ 广告接口返回 204 空响应 │
        └────────┬──────────┘   └───────────┬───────────┘
                 │                           │
                 └───────────┬───────────────┘
                             ▼
                      真实上游 DNS
            (AdGuard DNS / 阿里 DoH / ...)
```

**双层拦截逻辑：**

| 层级 | 工具 | 拦截方式 | 优势 | 局限 |
|------|------|----------|------|------|
| L1 | AdGuardHome | DNS 解析阶段拦截广告域名 | 全屋生效，无需客户端配置 | 无法处理 DoH/IP 直连/加密广告 |
| L2 | mitmproxy | 解密 HTTPS 流量，按 URL 规则拦截 | 精准拦截 App 内广告接口 | 需安装根证书，SSL Pinning 的 App 无效 |

---

## 二、目录结构

```
AdGuardHome/
├── docker-compose.yml              # 服务编排（AdGuardHome + mitmproxy）
├── adguard/
│   ├── conf/
│   │   └── AdGuardHome.yaml        # AdGuardHome 预配置文件（账号/规则/上游DNS）
│   └── work/                       # AdGuardHome 数据（持久化）
├── mitmproxy/
│   ├── scripts/
│   │   └── block_ads.py            # 广告拦截核心脚本
│   ├── rules/
│   │   └── hongguo-blocklist.txt   # 红果短剧 & 国内广告黑名单
│   └── certs/                      # mitmproxy 根证书（自动生成）
├── pf/
│   └── adguard.anchor              # pf 端口转发规则（53 → 8053）
├── certs-export/                   # 导出的证书（供设备安装）
├── scripts/
│   ├── init.sh                     # 环境初始化 & 前置检查
│   ├── start.sh                    # 启动服务
│   ├── stop.sh                     # 停止服务
│   ├── status.sh                   # 查看状态 & 拦截日志
│   ├── export-cert.sh              # 导出 mitmproxy 根证书
│   ├── pf-enable.sh                # 启用 pf 端口转发
│   └── pf-disable.sh               # 关闭 pf 端口转发
└── README.md
```

---

## 三、快速开始

### 0. 前置要求

- macOS（已在 macOS 上验证）
- [Docker Desktop](https://www.docker.com/products/docker-desktop) 已安装并启动
- 至少 1GB 可用磁盘空间

### 1. 初始化检查

```bash
cd /Users/51pwn/MyWork/AdGuardHome
./scripts/init.sh
```

脚本会检查 Docker、端口 53 占用等。若端口 53 被占用，见下方「常见问题」。

### 2. 启动服务

```bash
./scripts/start.sh
```

启动后两个容器运行：

- **AdGuardHome** Web UI: http://localhost:3001
- **AdGuardHome** DNS: 容器内 53 → 宿主机 8053（通过 pf 转发到标准 53）
- **mitmproxy** 代理: `http://localhost:8082`
- **mitmproxy** Web UI: http://localhost:8081 （密码: `mitmproxy`，或直接访问 `http://localhost:8081/?token=mitmproxy`）

> ⚠️ **macOS mDNSResponder 无法停止**：现代 macOS 的 SIP 保护机制不允许停止
> `mDNSResponder`（执行 `launchctl unload` 会报 `Input/output error`）。
> 本项目采用 **pf 端口转发方案**：保留 mDNSResponder（Bonjour/AirDrop 正常），
> 用 pf 将局域网发往 Mac 53 端口的 DNS 请求转发到 AdGuardHome(8053)。
> 详见下方「pf 端口转发配置」。

### 3. 配置 pf 端口转发（让手机用标准 53 端口访问 DNS）

```bash
./scripts/pf-enable.sh
```

该脚本会：
1. 加载 pf 规则，将 `en0:53` 转发到 `127.0.0.1:8053`（仅局域网设备）
2. 启用 pf
3. 将 Mac 自身 DNS 设为公共 DNS（`223.5.5.5`, `119.29.29.29`）

> 需要 sudo 权限。关闭转发：`./scripts/pf-disable.sh`
>
> ⚠️ **Mac 自身不经过 AdGuardHome 过滤**：macOS pf 对 `lo0`（本地回环）的
> 端口转发不可靠，因此 Mac 自身使用公共 DNS，仅局域网设备（手机等）走 AdGuardHome。

### 4. AdGuardHome 已预配置完成

AdGuardHome 已通过配置文件预初始化，无需手动走安装向导。登录信息：

| 项目 | 值 |
|------|-----|
| Web UI | http://localhost:3001 |
| 用户名 | `admin` |
| 密码 | `admin123` |

**已配置的上游 DNS**（国内可用）：
- `https://dns.alidns.com/dns-query`（阿里 DoH）
- `223.5.5.5`（阿里 DNS）
- `119.29.29.29`（DNSPod）

**已订阅的过滤规则**（6 个源 + 自定义，共约 52.8 万条）：

| 规则源 | 条数 | 覆盖范围 |
|--------|------|----------|
| anti-AD | 96,292 | 中文广告最全：国产 App、视频网站、挂马 |
| AdGuard DNS filter | 190,056 | 全球广告网络：Google、Facebook、Criteo 等 |
| AdRules 大圣净化 | 136,189 | 中文聚合规则（合并多个中文源） |
| hagezi Pro Mini | 102,624 | 全球广告/跟踪器/恶意域名 |
| 乘风广告过滤规则(cjx) | 1,820 | 国内网站弹窗/骚扰类补充 |
| AWAvenue 秋风广告规则 | 976 | **国产 App 广告 SDK 专杀**（字节、腾讯、阿里、百度、京东、快手等联盟） |
| 用户自定义规则 | 40+ | 红果短剧专项 + 拼多多全系封禁 |

> 所有订阅源均走 **jsdelivr CDN**（raw.githubusercontent.com 被墙），每 24 小时自动更新。
> HalfLife 规则源已失效（GitHub 仓库迁移/删除），改用乘风规则补充。
> 如需添加更多规则：Web UI → 过滤器 → DNS 封锁列表 → 添加封锁列表

**主要广告厂商覆盖情况**：

| 厂商 | 覆盖方式 |
|------|----------|
| 字节系（穿山甲/groMore/电商） | AWAvenue + 自定义（`pangolin`、`ecombdimg`、`ad.toutiao.com`） |
| 拼多多/Temu | 自定义全系封禁 11 个域名（见 5.4 节） |
| 腾讯广告（优量汇 gdt.qq.com） | 自定义 + 各订阅源 |
| 阿里/百度/京东联盟 | anti-AD + AWAvenue + AdRules |
| Google/Facebook 系 | AdGuard DNS filter + hagezi |
| 数据埋点（友盟、CNZZ、TalkingData） | 自定义 + hagezi |

> 如需修改密码：Web UI → 设置 → 常规设置 → 用户设置

### 5. 导出 mitmproxy 根证书

```bash
./scripts/export-cert.sh
```

证书会导出到 `certs-export/` 目录，包含 `.pem`、`.cer`、`.p12` 格式。

---

## 四、设备配置

### 4.1 macOS 本机

**DNS 配置：**

执行 `./scripts/pf-enable.sh` 后，Mac 自身 DNS 自动设为公共 DNS（`223.5.5.5`, `119.29.29.29`），
Mac 上网不受 AdGuardHome 影响。仅局域网设备（手机等）的 DNS 请求经 pf 转发到 AdGuardHome。

> 若需 Mac 自身也走 AdGuardHome 过滤，可手动设置系统 DNS 为 `127.0.0.1`，
> 但需确保有服务监听 53 端口（macOS pf 对 lo0 转发不可靠，不推荐）。

**mitmproxy 根证书安装：**

1. 双击 `certs-export/mitmproxy-ca-cert.pem`
2. 打开「钥匙串访问」→ 找到 `mitmproxy` 证书
3. 双击 → 信任 → 「使用此证书时」选择「始终信任」

**系统代理配置（可选，让本机 HTTP 流量走 mitmproxy）：**

1. 系统设置 → 网络 → 详细信息 → 代理
2. 勾选「网页代理(HTTP)」和「安全网页代理(HTTPS)」
3. 服务器填 `127.0.0.1`，端口 `8082`

> 注意：macOS 本机流量可能因 App Store 等系统服务使用证书绑定而无法解密，属正常现象。

### 4.2 iOS（iPhone / iPad）

确保手机与 Mac 在同一局域网，先查 Mac 的局域网 IP（如 `192.168.0.128`）。

以下示例以 Mac IP `192.168.0.128` 为例，实际替换为你自己的 Mac IP。

**a. 配置 DNS（只填一条）：**

1. 设置 → Wi-Fi → 点击当前 Wi-Fi 的 ⓘ
2. 配置 DNS → 手动 → 添加服务器：`192.168.0.128`
3. 删除其他所有 DNS 服务器（只保留这一条，否则广告请求可能绕过过滤）
4. 存储

> ✅ AdGuardHome 通过 pf 转发监听标准 53 端口，iOS 直接使用 Mac IP 即可，**无需安装任何 App**。

**b. 配置 HTTP 代理（用于拦截 App 内嵌广告，推荐开启）：**

1. 设置 → Wi-Fi → 当前 Wi-Fi ⓘ → 配置代理 → 手动
2. 服务器：`192.168.0.128`，端口：`8082`
3. 存储

> ✅ **红果短剧等字节系 App 的 SSL Pinning 已解决**：
> mitmproxy 配置了 `--ignore-hosts`，对字节系/红果相关域名（snssdk.com、toutiao.com、
> hongguo.com、fqnovel.com、bdurl.net 等）**直接透传，不做 SSL 解密**，
> App 的证书绑定验证通过，视频可正常播放。
> 广告域名（ad.toutiao.com 等）由 DNS 层拦截，内嵌广告接口由 mitmproxy 拦截。
>
> iOS 没有"绕过代理"字段，内网服务透传由 mitmproxy 的 `ignore-hosts` 配置处理。

**c. 下载 mitmproxy 根证书：**

1. 手机 Safari 浏览器访问 `http://mitm.it`
2. 点击「Apple」图标下载证书描述文件
3. 弹出「下载配置描述文件」时点允许

**d. 安装并信任证书：**

1. 设置 → 通用 → **VPN 与设备管理** → 点击「mitmproxy」描述文件 → 安装（输入锁屏密码）
2. 设置 → 通用 → 关于本机 → 滑到底 → **证书信任设置** → 开启「mitmproxy」完全信任

> ⚠️ 第 2 步「证书信任设置」是关键，不开启的话 HTTPS 流量无法解密，App 会连不上网。

### 4.3 Android

**DNS 配置：**

- **方法一（推荐）**：Wi-Fi 高级设置 → IP 设置 → 静态 → DNS 1 填 Mac 局域网 IP
  - AdGuardHome 使用标准 53 端口，Android 可直接使用，无需额外配置
- **方法二**：使用「私人 DNS」功能（Android 9+）
  - 设置 → 网络和互联网 → 私人 DNS → 主机名填入 AdGuardHome 的 DoH 地址
  - 需先给 AdGuardHome 配置域名（见 AdGuardHome 设置 → 加密设置）

**安装 mitmproxy 根证书：**

1. 将 `mitmproxy-ca-cert.cer` 传到手机
2. 设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书
3. 选择 `.cer` 文件安装

**配置代理：**

1. 设置 → Wi-Fi → 长按当前网络 → 修改网络 → 高级选项
2. 代理：手动 → 主机名：Mac 局域网 IP，端口：`8082`
3. 保存

> ⚠️ **Android 7+ 注意**：用户安装的 CA 证书默认不被 App 信任。
> 若红果短剧等 App 不信任用户证书，mitmproxy 无法解密其 HTTPS 流量。
> 解决方案：
> - **方案 1**：Android 7 以下设备 / 已 Root 设备将证书安装到系统证书目录
> - **方案 2**：使用 AdGuard for Android（本地 VPN 模式，自带证书注入）
> - **方案 3**：仅依赖 AdGuardHome DNS 层过滤（效果较弱但无需证书）

---

## 五、红果短剧广告拦截专项

### 5.1 工作原理

红果短剧（字节跳动旗下）的广告请求主要有两类：

1. **广告素材域名**：如 `ad.toutiao.com`、`api-access.skq-one.com` 等
   → AdGuardHome DNS 层直接拦截（返回 0.0.0.0）
2. **广告接口 API**：内嵌在业务域名（如 `*.snssdk.com`）中，路径含 `/ad/`、`/feed/ad`
   → mitmproxy 解密 HTTPS 后按路径规则拦截，返回 204 空响应

### 5.2 SSL Pinning 解决方案（关键）

红果短剧等字节系 App 启用了 **SSL Pinning（证书绑定）**，App 会校验服务器证书指纹，
mitmproxy 的自签证书会被拒绝，导致所有 HTTPS 请求失败、视频无法播放。

**解决方案：`--ignore-hosts` 直接透传**

在 `docker-compose.yml` 中，mitmproxy 启动时配置 `--ignore-hosts` 参数，
对字节系/红果相关域名**不做 SSL 解密，直接转发 TCP 流量**：

```yaml
command:
  - mitmweb
  - --ignore-hosts
  - "snssdk\\.com|toutiao\\.com|hongguo\\.com|amemv\\.com|ixigua\\.com|douyinvod\\.com|bytedance\\.com|bytedns1\\.com|bytedns\\.net|aioho\\.com|gtvvod\\.com|huoshanstatic\\.com|douyin\\.com|fqnovel\\.com|bdurl\\.net"
```

**效果：**
- App 直接与真实服务器握手，看到真实证书 → SSL Pinning 验证通过 → 视频正常播放
- 广告域名（`ad.toutiao.com` 等）在 DNS 层被拦截，App 无法解析 → 广告无法加载
- 其他非字节系域名的广告仍由 mitmproxy 拦截

> ⚠️ **注意**：必须用 `--ignore-hosts` 命令行选项，不能用 `--set ignore_hosts=`
> （后者在当前 mitmproxy 版本不生效，会导致 SSL 仍被拦截）。

### 5.3 mitmproxy 的 DNS 必须走 AdGuardHome（关键）

手机开启 HTTP 代理后，**域名解析发生在 mitmproxy 容器内**，而不是手机上。
如果 mitmproxy 容器使用公共 DNS（如 223.5.5.5），会出现致命漏洞：

```
手机（代理开） → mitmproxy
  ├─ 域名解析：用公共 DNS 直接解析 → 绕过 AdGuardHome
  ├─ 字节系域名 → --ignore-hosts 透传 → block_ads.py 看不到内容
  └─ 结果：ad.toutiao.com 等广告域名两层拦截全部失效，广告漏网
```

因此 `docker-compose.yml` 中 mitmproxy 的 `dns` 第一项必须指向
AdGuardHome 容器（固定 IP `172.20.0.2`）：

```yaml
adguardhome:
  networks:
    ad-net:
      ipv4_address: 172.20.0.2   # 固定 IP，供 mitmproxy 引用

mitmproxy:
  dns:
    - 172.20.0.2    # AdGuardHome（必须排第一）
    - 223.5.5.5     # 兜底
    - 119.29.29.29
```

效果：即使流量被透传，广告域名在**解析阶段**就被 AdGuardHome 拦死
（返回 0.0.0.0），连接直接失败，广告无法加载；视频域名有白名单不受影响。

### 5.4 规则文件

黑名单规则位于 `mitmproxy/rules/hongguo-blocklist.txt`，包含：

- 字节跳动广告 SDK 域名
- 字节电商广告素材源（`ecombdapi.com`、`ecombdimg.com`——红果"拼多多广告"的实际加载源）
- 拼多多全系封禁 11 个域名：`pinduoduo.com`、`yangkeduo.com`、`pddpic.com`、
  `pddugc.com`、`pddcdn.com`、`temu.com`、`pddpay.com`、`pinduoduo.net`、
  `pdd.net.cn`、`pddlive.com`、`yangshengba.com`
- 国内常见广告联盟域名（友盟、TalkingData、广点通等）
- 视频广告常见域名
- URL 关键词规则（`/ad/`、`/ads/`、`/api/ad/*` 等）
- 红果短剧专属广告接口路径

> 以上域名同时写入 AdGuardHome 自定义规则（`adguard/conf/AdGuardHome.yaml` 的
> `user_rules`），实现 DNS 层 + 代理层双重拦截。

**修改规则后无需重启**，脚本每 60 秒自动重载。也可重启 mitmproxy 容器立即生效：

```bash
docker compose restart mitmproxy
```

### 5.5 如何发现新的广告域名（抓包分析）

若发现红果短剧仍有广告，按以下步骤抓包分析：

1. 打开 mitmproxy Web UI: http://localhost:8081
2. 在手机上操作红果短剧，观看出现广告的场景
3. 在 Web UI 中筛选 `snssdk.com`、`toutiao.com`、`byteimg.com` 等域名
4. 观察广告出现时刻的请求，记录其 URL 路径特征
5. 将发现的广告域名或 URL 关键词追加到 `mitmproxy/rules/hongguo-blocklist.txt`
6. 查看拦截日志确认效果：

```bash
tail -f mitmproxy/certs/blocked.log
```

### 5.6 验证拦截效果

```bash
# 查看 mitmproxy 拦截日志
./scripts/status.sh

# 实时查看拦截
tail -f mitmproxy/certs/blocked.log

# AdGuardHome 查询日志（Web UI → 日志）
# 可看到被拦截的 DNS 查询（状态为被过滤器拦截）
```

---

## 六、日常运维

### 启动 / 停止

```bash
./scripts/start.sh     # 启动
./scripts/stop.sh      # 停止
./scripts/status.sh    # 状态
```

### 查看日志

```bash
# 所有服务日志
docker compose logs -f

# 仅 mitmproxy
docker compose logs -f mitmproxy

# 仅 AdGuardHome
docker compose logs -f adguardhome
```

### 更新规则

AdGuardHome 的订阅规则会自动更新。mitmproxy 的黑名单手动编辑后自动生效：

```bash
# 编辑黑名单
vim mitmproxy/rules/hongguo-blocklist.txt

# 立即重载（可选，否则等 60 秒）
docker compose restart mitmproxy
```

### 升级镜像

```bash
docker compose pull
docker compose up -d
```

### 备份与恢复

只需备份两个目录即可完整迁移：

```bash
# 备份
tar czf adguard-backup.tar.gz adguard/ mitmproxy/certs/

# 恢复
tar xzf adguard-backup.tar.gz
```

---

## 七、常见问题（FAQ）

### Q1: mDNSResponder 无法停止（Input/output error）？

现代 macOS 的 **SIP（系统完整性保护）** 不允许停止 `mDNSResponder`，
执行 `launchctl unload` 会报 `Unload failed: 5: Input/output error`。

**本项目的解决方案：pf 端口转发**（无需停止 mDNSResponder）：

```bash
./scripts/pf-enable.sh
```

原理：
- mDNSResponder 继续占用 53 端口，负责 Mac 自身 DNS + Bonjour/AirDrop
- pf 防火墙将**局域网其他设备**发往 Mac 53 端口的请求转发到 AdGuardHome(8053)
- Mac 自身使用公共 DNS（`223.5.5.5`），不经过 AdGuardHome

**优势**：
- ✅ Bonjour/AirDrop/AirPlay 完全正常
- ✅ 手机用 Mac IP 作 DNS（标准 53 端口，无需 App）
- ✅ Mac 自身上网不受影响
- ✅ 不破坏任何系统服务

### Q2: 红果短剧开启代理后视频无法播放？

这是因为红果短剧启用了 **SSL Pinning**。本项目已通过 `--ignore-hosts` 解决此问题：
- 字节系域名直接透传，不做 SSL 解密 → SSL Pinning 验证通过 → 视频正常播放
- 广告域名由 DNS 层拦截

如果仍无法播放，请检查：
1. mitmproxy 容器是否使用 `--ignore-hosts`（而非 `--set ignore_hosts=`）
2. 红果短剧相关域名是否在 ignore-hosts 列表中
3. 查看 mitmproxy 日志是否有 `Client TLS handshake failed`：
   ```bash
   docker compose logs mitmproxy | grep "TLS handshake failed"
   ```
   若有，说明该域名不在 ignore-hosts 中，需将其域名加入列表并重启 mitmproxy。

### Q3: 红果短剧广告仍未被拦截？

可能原因：

1. **广告走 DoH/DoT**：App 内置加密 DNS，绕过系统 DNS。
   → 在 AdGuardHome 中开启「DNS 安全设置」→ 拦截 DoH/DoT 请求
2. **广告域名不在黑名单**：
   → 按 5.4 节抓包分析，补充规则到 `mitmproxy/rules/hongguo-blocklist.txt`
3. **广告使用新域名**：
   → 在 mitmproxy Web UI 中观察广告请求，将域名加入 AdGuardHome 用户规则

### Q4: mitmproxy 启动后手机无法上网？

- 检查 mitmproxy 容器是否正常：`docker compose ps`
- 检查手机代理是否指向正确的 Mac IP 和端口 8082
- 检查根证书是否已正确安装并信任
- 查看 mitmproxy 日志：`docker compose logs mitmproxy`

### Q5: 安装证书后仍有 `SSL handshake failed`？

- 该 App 启用了 SSL Pinning，mitmproxy 无法解密
- **解决方案**：将该 App 的域名加入 mitmproxy 的 `--ignore-hosts` 列表（见 5.2 节），
  让其流量直接透传，不做 SSL 解密
- 此时该 App 的广告仅能依赖 AdGuardHome DNS 层过滤

### Q6: 如何让全屋设备都走 AdGuardHome？

登录路由器管理后台，将 LAN 口 DNS 改为运行 AdGuardHome 的 Mac 的局域网 IP。
注意：Mac 需保持开机，且 AdGuardHome 容器运行中。

### Q7: Docker Desktop 占用资源高？

可在 Docker Desktop → Settings → Resources 中限制 CPU 和内存。
AdGuardHome 和 mitmproxy 资源占用很低，2GB 内存足够。

---

## 八、进阶：增强拦截效果

### 8.1 维护 ignore-hosts 列表

若发现新的 App 因 SSL Pinning 无法使用，将其域名加入 `docker-compose.yml` 的
`--ignore-hosts` 列表，用竖线 `|` 分隔：

```yaml
- --ignore-hosts
- "现有域名|新域名\\.com"
```

修改后重启 mitmproxy：

```bash
docker compose up -d mitmproxy
```

### 8.2 配合第三方代理工具（iOS）

由于 AdGuard 官方 App 不在中国区 App Store，iOS 用户可使用以下替代方案：

- **Shadowrocket / Quantumult X**：配置 MITM + 重写规则，效果最好
- **Ad Blocker Pro**（国区 ¥38）：Safari 广告拦截 + DNS 过滤

本项目的黑名单规则可直接迁移为 URL 规则。

### 8.3 路由器级部署

若有软路由（OpenWrt/iKuai），可将 AdGuardHome 和 mitmproxy 部署在路由器上，
实现全屋透明代理，无需每台设备单独配置。

---

## 九、法律与伦理声明

本项目仅用于个人学习与研究，过滤自己设备上的广告。
请勿用于：
- 拦截他人设备的流量
- 破解付费内容
- 任何违反当地法律法规的用途

使用 HTTPS 中间人代理可能违反部分 App 的服务条款，请自行评估风险。

---

## 十、参考链接

- [AdGuardHome 官方文档](https://github.com/AdguardTeam/AdGuardHome/wiki)
- [mitmproxy 官方文档](https://docs.mitmproxy.org/)
- [anti-AD 广告过滤规则](https://github.com/privacy-protection-tools/anti-AD)
- [红果短剧广告拦截讨论](https://github.com/AdguardTeam/AdguardFilters/issues)
