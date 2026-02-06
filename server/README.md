# LanRead Server

基于 FastAPI 的轻量级服务，用于安全地向 iOS 客户端分发大模型 API Key，并为后续用户注册、登录和阅读数据同步留出扩展空间。

## 特性

- HMAC 请求签名校验（`client_id` + `nonce` + `timestamp`）防止重放与伪造。
- 严格的 HTTPS 要求与 HSTS 响应头，默认拒绝明文请求。
- `.env` 配置驱动，方便本地/生产环境切换。
- 模块化的 `app/` 目录，便于后续添加用户与阅读数据相关路由。

---

## 快速开始（本地开发 / 本地自签证书）

1. 准备运行时：

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .

```

1. 创建配置：

```bash
cp .env.example .env
# 填写 ISLA_API_KEY、ISLA_API_ENDPOINT、ISLA_AI_MODEL、ISLA_CLIENT_ID、ISLA_CLIENT_SECRET，并指向 TLS 证书路径。
# 若需前端跨域，设置 ISLA_ALLOWED_ORIGINS 为逗号分隔值或 JSON 数组；留空/[] 则不启用 CORS。

```

1. 生成本地证书（示例，生产请使用受信任证书）：

```bash
# 推荐：使用脚本生成，默认 CN=localhost，证书输出到 server/certs
./scripts/generate-cert.sh
# 指定域名/有效期，并强制覆盖已有文件
./scripts/generate-cert.sh --name example.com --days 365 --force
# 仅有内网/云主机 IP 时，将 CN 设为该 IP（自动写入 SAN），可选额外 --ip 添加更多 IP
./scripts/generate-cert.sh --name 172.16.9.224 --ip 172.16.9.224 --days 365 --force

```

证书生成或拷贝后，容器会以非 root 用户 (默认 uid/gid=1000) 运行，请确保 TLS 文件可读：

```bash
sudochown 1000:1000 certs/server.crt certs/server.key
sudochmod 640 certs/server.crt certs/server.key
# 若需要自定义 UID/GID，可在运行脚本前设置 CERT_UID/CERT_GID 环境变量

```

1. 启动服务（带 TLS，示例用于本地/内网环境）：

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile certs/server.key \
  --ssl-certfile certs/server.crt

```

1. 验证：

```bash
curl -k -X POST https://localhost:8443/v1/keys/ai \
  -H"Content-Type: application/json" \
  -d'{"client_id":"your-client-id","nonce":"123","timestamp":1700000000,"signature":"hmac_hex"}'

```

---

## 端点

- `GET /health` — 健康检查。
- `GET /privacy` — 静态隐私政策页面（客户端/审核可直接访问）。
- `POST /v1/keys/ai` — 返回 AI API Key 以及可远程调配的 `api_endpoint`、`model`。请求体需签名，响应默认带 `Cache-Control: no-store`。
    - 签名计算：`HMAC_SHA256(client_id + "." + nonce + "." + timestamp, client_secret)`，并使用十六进制字符串传输。
- `POST /v1/oauth/notion/exchange` — 使用同一套签名校验机制代理 Notion OAuth `code` 换 token（服务端使用 HTTP Basic Auth 调用 Notion，避免在 iOS 内存放 `client_secret`）。成功返回 `access_token` 与工作区信息；失败返回 `{error, error_description?, status_code}`；响应头强制 `Cache-Control: no-store`。
- `POST /v1/metrics` — 采集客户端上报的 AI/API 调用指标，需携带 `X-Metrics-Key`（默认与 `client_secret` 相同，可单独配置 `ISLA_METRICS_INGEST_TOKEN`）。请确保与 iOS 构建时的 `SECURE_SERVER_METRICS_TOKEN` 一致，否则会被 401 拒绝。
- `GET /admin/metrics/ads` — 登录后返回最近 7 天广告加载成功/失败次数及失败原因统计，数据由客户端上报（`source=ads`）。
- `GET /admin/metrics` — 登录后查看实时统计面板（`ISLA_DASHBOARD_USERNAME`/`ISLA_DASHBOARD_PASSWORD`），数据持久化在 `ISLA_METRICS_DATA_FILE`（默认 `data/metrics.jsonl`，保留数量由 `ISLA_METRICS_MAX_EVENTS` 控制）。

> 说明：若访问 / 返回 404 属于正常现象（API-only 服务不一定提供根路径页面）。建议用 /health 做可用性检查。
> 

## 日志与监控

- 应用日志默认写入 `app/logs/server.log`（由 `ISLA_LOG_FILE` 控制，使用相对路径时以 `app/` 目录为基准），同时也会输出到 stdout，并按 `ISLA_LOG_MAX_BYTES`/`ISLA_LOG_BACKUP_COUNT` 进行轮转。
- 日志等级由 `ISLA_LOG_LEVEL` 控制，可设置为 `INFO` 或 `DEBUG` 以便排查。
- 指标事件写入 `ISLA_METRICS_DATA_FILE`，默认路径为 `app/data/metrics.jsonl`，文件不存在会自动创建；收到上报后可在日志中搜索 `Metrics ingested` 以确认写入成功。

---

## 安全建议

- 生产环境务必使用受信任证书并保持 `ISLA_REQUIRE_HTTPS=true`（配合反向代理的 `X-Forwarded-Proto` 识别）。
- 为不同客户端分配独立的 `client_id`/`client_secret`，定期轮换。
- 配置 Notion OAuth 时请仅在服务端 `.env` 设置 `ISLA_NOTION_CLIENT_ID` / `ISLA_NOTION_CLIENT_SECRET`（兼容 `NOTION_CLIENT_ID` / `NOTION_CLIENT_SECRET`），不要下发到客户端。
- 部署时尽量仅暴露必要端口：推荐只暴露 `80/443`，后端应用端口仅本机监听。

---

## 生产部署：TLS 终止在反向代理（推荐，已在 AWS EC2 跑通）

### 目标架构（方案一）

- 公网入口：`https://isla-reader.top`（或 `www.isla-reader.top`）走 **443**，证书由 **Caddy + Let’s Encrypt** 自动签发与续期
- 后端应用：Uvicorn 只在本机提供 HTTP：`127.0.0.1:8000`
- 安全组仅放行：TCP `80/443`（迁移完成后关闭 `8443`）

---

### A. DNS / 安全组准备

1. DNS 解析：
- `@` → A → 指向 EC2 公网 IP（或 Elastic IP）
- `www` → A → 指向同一 IP
1. AWS Security Group（入站）：
- 允许 `TCP 80`（Let’s Encrypt 校验 + HTTP→HTTPS 重定向）
- 允许 `TCP 443`（正式 HTTPS 入口）
- （可选）迁移完成后关闭 `TCP 8443`

> 推荐：绑定 Elastic IP，避免实例公网 IP 变化导致域名失效。
> 

---

### B. 后端：Uvicorn 改为本机 HTTP（127.0.0.1:8000）

1. 进入项目并启用 venv：

```bash
cd /home/ec2-user/Isla-Reader/server
source .venv/bin/activate

```

1. 确认 `.env` 已在 `server/` 目录且变量齐全（例如 `ISLA_API_ENDPOINT/ISLA_AI_MODEL/ISLA_API_KEY/ISLA_CLIENT_ID/ISLA_CLIENT_SECRET` 等）。

> systemd 模式下建议用 EnvironmentFile 显式加载 .env（见下文）。
> 
1. 手动验证可启动：

```bash
uvicorn app.main:app \
  --host 127.0.0.1 \
  --port 8000 \
  --proxy-headers \
  --forwarded-allow-ips 127.0.0.1

```

1. 验证本机访问：

```bash
curl -I http://127.0.0.1:8000/health

```

---

### C. 用 systemd 托管 Uvicorn（推荐）

创建 `/etc/systemd/system/isla-api.service`（示例为 AWS 上的实际路径）：

```
[Unit]
Description=Isla FastAPI (Uvicorn)
After=network.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/home/ec2-user/Isla-Reader/server

# 直接加载项目目录下 .env（需是 KEY=VALUE 格式，不要写 export）
EnvironmentFile=-/home/ec2-user/Isla-Reader/server/.env

Environment=PYTHONUNBUFFERED=1

# 使用 venv 内的 uvicorn，避免 systemd 下找不到命令
ExecStart=/home/ec2-user/Isla-Reader/server/.venv/bin/uvicorn app.main:app \
  --host 127.0.0.1 \
  --port 8000 \
  --proxy-headers \
  --forwarded-allow-ips 127.0.0.1

Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target

```

加载并启动：

```bash
sudo systemctl daemon-reload
sudo systemctlenable --now isla-api
sudo systemctl status isla-api --no-pager -l

```

查看日志：

```bash
sudo journalctl -u isla-api -e --no-pager

```

确认只监听本机：

```bash
ss -lntp | grep 8000
# 应看到 127.0.0.1:8000

```

---

### D. 反向代理：Caddy（Amazon Linux 2023 实操版，已跑通）

> 说明：Amazon Linux 2023 上不一定直接有官方仓库包。这里使用 GitHub Release 二进制安装方式。
> 

### 1) 安装依赖（setcap 所在包）

```bash
sudo dnf install -y libcap
command -vsetcap

```

### 2) 下载并安装 Caddy（示例版本 v2.10.0）

```bash
cd /tmp
rm -f caddy.tar.gz caddy

ARCH="$(uname -m)"
if ["$ARCH" ="x86_64" ];then GOARCH="amd64"; \
elif ["$ARCH" ="aarch64" ];then GOARCH="arm64"; \
elseecho"Unsupported arch: $ARCH";exit 1;fi

VER="2.10.0"
curl -fL -o caddy.tar.gz \
"https://github.com/caddyserver/caddy/releases/download/v${VER}/caddy_${VER}_linux_${GOARCH}.tar.gz"

tar -xzf caddy.tar.gz caddy
sudomv caddy /usr/bin/caddy
sudochmod 755 /usr/bin/caddy
sudosetcap cap_net_bind_service=+ep /usr/bin/caddy

caddy version

```

### 3) 创建 caddy 用户与目录

```bash
sudo useradd --system --home /var/lib/caddy --shell /usr/sbin/nologin caddy ||true
sudomkdir -p /etc/caddy /var/lib/caddy /var/log/caddy
sudochown -R caddy:caddy /var/lib/caddy /var/log/caddy
sudochmod 755 /etc/caddy

```

### 4) 配置 `/etc/caddy/Caddyfile`

```
isla-reader.top www.isla-reader.top {
    reverse_proxy 127.0.0.1:8000

    # 可选：访问日志
    log {
        output file /var/log/caddy/access.log
    }
}

```

格式化（可选）：

```bash
sudo caddyfmt --overwrite /etc/caddy/Caddyfile

```

### 5) 配置 systemd：`/etc/systemd/system/caddy.service`

> 关键点：必须授予绑定 80/443 的能力。另外，若设置了 NoNewPrivileges=true，建议使用 AmbientCapabilities 显式授权。
> 

```
[Unit]
Description=Caddy web server
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy

# 允许绑定 80/443
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile

WorkingDirectory=/var/lib/caddy
StateDirectory=caddy
RuntimeDirectory=caddy

LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target

```

启动并设置开机自启：

```bash
sudo systemctl daemon-reload
sudo systemctlenable --now caddy
sudo systemctl status caddy --no-pager -l

```

查看日志（证书签发失败/解析不对时这里最关键）：

```bash
sudo journalctl -u caddy -e --no-pager

```

---

### E. 验证（生产）

1. 验证证书与 HTTPS：

```bash
curl -Iv https://isla-reader.top
curl -Iv https://www.isla-reader.top

```

期望看到：

- `issuer: Let's Encrypt`
- `SSL certificate verify ok.`
- 响应头包含 `via: 1.1 Caddy`
- `server: uvicorn`（代表反向代理成功转到后端）
1. 验证健康检查：

```bash
curl -I https://isla-reader.top/health

```

1. 验证业务接口（示例）：

```bash
curl -X POST https://isla-reader.top/v1/keys/ai \
  -H"Content-Type: application/json" \
  -d'{"client_id":"your-client-id","nonce":"123","timestamp":1700000000,"signature":"hmac_hex"}'

```

---

### F. 迁移收口（建议）

- iOS 客户端改为走 `https://isla-reader.top`（443）后：
    - AWS 安全组关闭 `8443`
    - 后端服务仅本机监听 `127.0.0.1:8000`（不暴露公网）

---

## Docker 部署脚本

- 位置：`server/scripts/`
- `deploy.sh`：在干净主机上构建镜像并运行容器。默认读取 `server/.env`，挂载 `server/certs` 为 `/certs`，映射端口 `8443`。
- `restart.sh`：拉取最新基础镜像、重建并重启容器（应用最新代码）。
- `stop.sh [--remove|-r]`：停止容器，`-remove` 同时删除容器。

示例：

```bash
cd server
./scripts/deploy.sh# 首次部署
# 更新代码后
./scripts/restart.sh
# 停止并删除容器
./scripts/stop.sh --remove

```

> 注意：若采用“反向代理终止 TLS”的生产方案，容器内的 8443 TLS 模式通常不再需要，对外只暴露 80/443 即可。
> 

---

## 维护脚本

- `clear-metrics.sh`：清空统计数据文件（默认读取 `.env` 的 `ISLA_METRICS_DATA_FILE`，相对路径按 `app/` 目录解析）。若服务正在运行，执行后请重启以清除内存缓存。

示例：

```bash
cd server
./scripts/clear-metrics.sh
```

---

## 后续扩展

- 在 `app/routers/` 添加用户注册/登录、阅读数据同步等路由。
- 若需要数据库支持，可在 `app/config.py` 中扩展连接配置并添加 ORM。

---

### 你现在可以直接做的一步小优化（可选但推荐）

你目前根路径 `/` 返回 404 是正常的，但为了更直观地验证“反代是否正常”，你可以在 Caddy 里把根路径重定向到 `/health`（可选）：

```
isla-reader.top www.isla-reader.top {
    @root path /
    redir @root /health 302

    reverse_proxy 127.0.0.1:8000
}

```

---

如果你愿意，我也可以按你仓库实际结构帮你输出一个 **git diff patch**（只改 README + 增加两个 systemd unit 示例文件），你直接 `git apply` 就能落地。你只要告诉我：你希望这些 systemd 示例放在仓库哪里（比如 `server/deploy/systemd/` 还是 `server/scripts/`）。
