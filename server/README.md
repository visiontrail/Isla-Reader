# Isla Reader Server

基于 FastAPI 的轻量级服务，用于安全地向 iOS 客户端分发大模型 API Key，并为后续用户注册、登录和阅读数据同步留出扩展空间。

## 特性
- HMAC 请求签名校验（`client_id` + `nonce` + `timestamp`）防止重放与伪造。
- 严格的 HTTPS 要求与 HSTS 响应头，默认拒绝明文请求。
- `.env` 配置驱动，方便本地/生产环境切换。
- 模块化的 `app/` 目录，便于后续添加用户与阅读数据相关路由。

## 快速开始
1) 准备运行时：
```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

2) 创建配置：
```bash
cp .env.example .env
# 填写 AI_KEY、CLIENT_ID、CLIENT_SECRET，并指向 TLS 证书路径
```

3) 生成本地证书（示例，生产请使用受信任证书）：
```bash
# 推荐：使用脚本生成，默认 CN=localhost，证书输出到 server/certs
./scripts/generate-cert.sh
# 或指定域名/有效期，并强制覆盖已有文件
./scripts/generate-cert.sh --name example.com --days 365 --force

# 手动 openssl 等价命令（供参考）
# mkdir -p certs
# openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
#   -keyout certs/server.key -out certs/server.crt \
#   -subj "/CN=localhost" \
#   -addext "subjectAltName = DNS:localhost,IP:127.0.0.1" \
#   -addext "keyUsage = critical, digitalSignature, keyEncipherment" \
#   -addext "extendedKeyUsage = serverAuth"
```

4) 启动服务（带 TLS）：
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile certs/server.key \
  --ssl-certfile certs/server.crt
```

5) 验证：
```bash
curl -k -X POST https://localhost:8443/v1/keys/ai \
  -H "Content-Type: application/json" \
  -d '{"client_id":"your-client-id","nonce":"123","timestamp":1700000000,"signature":"hmac_hex"}'
```

## 端点
- `GET /health` — 健康检查。
- `POST /v1/keys/ai` — 返回 AI API Key。请求体需签名，响应默认带 `Cache-Control: no-store`。
  - 签名计算：`HMAC_SHA256(client_id + "." + nonce + "." + timestamp, client_secret)`，并使用十六进制字符串传输。

## 安全建议
- 生产环境务必使用受信任证书并保持 `ISLA_REQUIRE_HTTPS=true`。
- 为不同客户端分配独立的 `client_id`/`client_secret`，定期轮换。
- 部署时将服务置于零信任或私网入口，仅暴露必要端口。

## Docker 部署脚本
- 位置：`server/scripts/`
- `deploy.sh`：在干净主机上构建镜像并运行容器。默认读取 `server/.env`，挂载 `server/certs` 为 `/certs`，映射端口 `8443`。
- `restart.sh`：拉取最新基础镜像、重建并重启容器（应用最新代码）。
- `stop.sh [--remove|-r]`：停止容器，`--remove` 同时删除容器。

示例：
```bash
cd server
./scripts/deploy.sh        # 首次部署
# 更新代码后
./scripts/restart.sh
# 停止并删除容器
./scripts/stop.sh --remove
```

## 后续扩展
- 在 `app/routers/` 添加用户注册/登录、阅读数据同步等路由。
- 若需要数据库支持，可在 `app/config.py` 中扩展连接配置并添加 ORM。
