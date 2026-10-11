# Dify v1 AI App Studio — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Dify v1 AI App Studio** (version label `v1` = Dify major version; Dify tags releases as `v1.x.y`) |
| Description | Visual agent & RAG builder with plugins, code sandbox, workers and vector DB. (77 chars) |
| Category | AI/ML |
| Tags | dify, llm, agents, rag, workflow, weaviate, ai |
| User input at deploy | **None.** All keys and passwords are generated. Optional later: email (`MAIL_TYPE` + SMTP/Resend vars). |

## Base market template

- **`TiT2V6` "Dify v1.17.1"** (470 projects, 66 active) — chosen as base: already on 1.17.1 with plugin daemon, sandbox, Weaviate and a complete API/worker variable set. Kept the variable set and service split; replaced MinIO, the hardcoded upstream keys and the two-domain layout.
- `V1xiql` "Dify" (1,882 projects, 372 active) — most deployed but unpinned (`latest`), MinIO + `mc` provisioning job + DB provisioning job, reference typos. Rejected as base; nothing taken.
- `dify-ai-workflow` (34 projects) — took the *idea* of a single-origin nginx gateway; its config (base64 in the start command, `nginx:latest`, `ipv6=off`, hardcoded MinIO password, no volumes on Weaviate/plugins) was not reused.
- No `_upstream` repos exist for this app. Market templates have no license → reference only.

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| Dify API / Worker / Beat / WebSocket | `langgenius/dify-api` | `1.17.1` | 2026-09-10 | 2026-10-10 |
| Dify Web | `langgenius/dify-web` | `1.17.1` | 2026-09-10 | 2026-10-10 |
| Plugin Daemon | `langgenius/dify-plugin-daemon` | `0.6.10-local` | 2026-08-07 | 2026-10-10 |
| Code Sandbox | `langgenius/dify-sandbox` | `0.2.15` | 2026-04-27 | 2026-10-10 |
| Agent Backend | `langgenius/dify-agent-backend` | `1.17.1` | 2026-09-10 | 2026-10-10 |
| Agent Sandbox | `langgenius/dify-agent-local-sandbox` (wrapped: `services/agent-sandbox`) | `1.17.1` | 2026-09-10 | 2026-10-10 |
| SSRF proxies | `ubuntu/squid` (wrapped: `services/ssrf-proxy`) | `6.6-24.04_beta` | image build 2025-11-24 | 2026-10-10 |
| Gateway | `nginx` (wrapped: `services/gateway`) | `1.30.5-alpine` | image build 2026-09-26 | 2026-10-10 |
| Weaviate | `semitechnologies/weaviate` | `1.39.11` | 2026-10-09 | 2026-10-10 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base | 2026-10-10 |
| Redis | `redis` | `8.2` | Railway base | 2026-10-10 |

- Plugin Daemon: Exact tag pinned by Dify 1.17.1 compose (0.6.11 appeared today, not yet paired with a Dify release).
- SSRF proxies: Upstream uses `ubuntu/squid:latest`; pinned to the Ubuntu 24.04 LTS build.
- Weaviate: Upstream pins 1.39.2; latest patch of the same minor.

Upgrade path: change every `1.17.1` tag together (API, API WebSocket, Worker, Worker Beat, Web, Agent Backend, and the `FROM` line in `services/agent-sandbox/Dockerfile`), and the Plugin Daemon / Sandbox / Weaviate tags to the values in the new release's `docker/docker-compose.yaml`. Migrations run automatically on the API service.

## Architecture

```
Internet ──HTTPS──▶ Gateway (nginx, only public domain)
                     ├─ /console/api /api /v1 /files /mcp /triggers /openapi ─▶ API :5001
                     ├─ /socket.io/ ───────────────────────────────────────────▶ API WebSocket :5001
                     ├─ /e/ (plugin endpoints) ────────────────────────────────▶ Plugin Daemon :5002
                     └─ / (console + published web apps) ──────────────────────▶ Web :3000
API / Worker / Beat ─▶ Postgres, Redis, Weaviate, Bucket (S3), Sandbox, Plugin Daemon, Agent Backend
Sandbox, API, Worker, plugins ─egress─▶ SSRF Proxy ─▶ internet (private ranges blocked)
Agent Backend ─▶ Agent Sandbox ─egress─▶ Agent SSRF Proxy ─▶ internet + Agent Stub + API /files only
```

**Why one gateway instead of separate Web and API domains.** Dify's console authenticates with HttpOnly cookies and CSRF tokens issued by the API. On Railway every generated domain is a sibling under `up.railway.app`, which is on the Public Suffix List, so Web and API on two generated domains are *cross-site*: cookies cannot be scoped to both and browsers that block third-party cookies (Safari, hardened Chrome/Firefox) break login. Upstream Dify itself ships behind one nginx origin (`CONSOLE_API_URL` empty = same origin). The Gateway reproduces upstream's routing table, so:

- one URL for console, published apps, Service API (`/v1`), MCP, triggers and plugin webhooks;
- no CORS/cookie-domain tuning; adding a custom domain is one domain on the Gateway plus `DIFY_PUBLIC_URL` (API) and `NEXT_PUBLIC_SOCKET_URL` (Web);
- the gateway resolves `*.railway.internal` per request (`resolver` from `/etc/resolv.conf`, IPv6-aware), so it boots before the upstreams and survives their redeploys.

Web, API and Plugin Daemon have **no** public domain.

### Deviations from upstream compose (and why)

- `nginx` → **Gateway** with Railway private DNS; no certbot (Railway terminates TLS).
- `init_permissions` dropped: API has no local storage (Bucket), so no chown step is needed.
- `SECRET_KEY` set explicitly (upstream may auto-generate one into the API storage dir, which would differ per container here).
- `MIGRATION_ENABLED=true` only on API (upstream sets it everywhere; Dify serialises with a Redis lock, but one migrator is cleaner).
- Squid configs re-created with the same ACL policy, minus `tcp_outgoing_address 0.0.0.0` (would break IPv6 private destinations needed by the agent proxy) and with a 32 MB memory cache instead of 256 MB.
- `local_sandbox` keeps one volume (`/home/dify`, where agent homes and home snapshots live); `/workspace` is ephemeral (Railway allows one volume per service).
- Docker network isolation between `local_sandbox` and `api` cannot be reproduced on Railway's flat private network (see Open questions).

## Services

Create in this order. Values are entered exactly as shown (Railway resolves `${{...}}`).

### Gateway

- **Source:** GitHub repo `baranberkay96/dify-railway`, root directory `/services/gateway` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** `/healthz` (timeout 120 s)
- **Public domain:** yes → target port `8080`
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port nginx listens on (public domain target). |
| `DIFY_WEB_UPSTREAM` | `${{Web.RAILWAY_PRIVATE_DOMAIN}}:3000` | Web (Next.js) private address. |
| `DIFY_API_UPSTREAM` | `${{API.RAILWAY_PRIVATE_DOMAIN}}:5001` | API private address. |
| `DIFY_SOCKET_UPSTREAM` | `${{API WebSocket.RAILWAY_PRIVATE_DOMAIN}}:5001` | API WebSocket private address (/socket.io). |
| `DIFY_PLUGIN_DAEMON_UPSTREAM` | `${{Plugin Daemon.RAILWAY_PRIVATE_DOMAIN}}:5002` | Plugin Daemon private address (/e/ plugin endpoints). |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `100M` | Max upload size through the gateway. |
| `NGINX_PROXY_TIMEOUT` | `3600s` | Proxy read/send timeout (long-running streams). |

### Web

- **Source:** Docker image `langgenius/dify-web:1.17.1`
- **Start command:** image default
- **Healthcheck:** `/signin` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Next.js listen port. |
| `HOSTNAME` | `::` | Listen on IPv4+IPv6. |
| `DEPLOY_ENV` | `PRODUCTION` | Deployment environment flag. |
| `CONSOLE_WEB_URL` | `${{API.CONSOLE_WEB_URL}}` | Public console URL (web prefix). |
| `SERVER_CONSOLE_API_URL` | `http://${{API.RAILWAY_PRIVATE_DOMAIN}}:5001` | Private API URL for server-side rendering requests. |
| `NEXT_PUBLIC_SOCKET_URL` | `wss://${{Gateway.RAILWAY_PUBLIC_DOMAIN}}` | Public WebSocket origin for collaboration (update with a custom domain). |
| `MARKETPLACE_API_URL` | `https://marketplace.dify.ai` | Plugin marketplace API. |
| `MARKETPLACE_URL` | `https://marketplace.dify.ai` | Plugin marketplace site. |
| `NEXT_PUBLIC_ENABLE_AGENT_V2` | `true` | Show the Agent (v2) builder, backed by Agent Backend + Agent Sandbox. |
| `NEXT_TELEMETRY_DISABLED` | `1` | Disable Next.js telemetry. |
| `TEXT_GENERATION_TIMEOUT_MS` | `60000` | Client timeout for text generation (ms). |
| `LOOP_NODE_MAX_COUNT` | `100` | Max loop iterations in workflows. |
| `MAX_ITERATIONS_NUM` | `99` | Max iteration-node items. |
| `MAX_PARALLEL_LIMIT` | `10` | Max parallel branches. |
| `MAX_TOOLS_NUM` | `10` | Max tools per agent. |
| `MAX_TREE_DEPTH` | `50` | Max workflow nesting depth. |
| `TOP_K_MAX_VALUE` | `10` | Max retrieval top-k in the UI. |
| `INDEXING_MAX_SEGMENTATION_TOKENS_LENGTH` | `4000` | Max chunk length for knowledge indexing. |
| `ALLOW_EMBED` | `false` | Allow embedding the console in iframes (published apps are always embeddable). |

### API

- **Source:** Docker image `langgenius/dify-api:1.17.1`
- **Start command:** image default
- **Healthcheck:** `/health` (timeout 600 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `MODE` | `api` | dify-api run mode. |
| `PORT` | `5001` | Port Railway health-checks and routes to. |
| `DIFY_BIND_ADDRESS` | `[::]` | Bind on IPv4+IPv6 so the private network can reach it. |
| `DIFY_PORT` | `5001` | Gunicorn listen port. |
| `SERVER_WORKER_AMOUNT` | `1` | Gunicorn worker processes (raise with more RAM/CPU). |
| `SERVER_WORKER_CLASS` | `gevent` | Gunicorn worker class. |
| `SERVER_WORKER_CONNECTIONS` | `10` | Concurrent connections per worker. |
| `GUNICORN_TIMEOUT` | `360` | Request timeout in seconds (long streaming responses). |
| `MIGRATION_ENABLED` | `true` | Run database migrations on boot (only this service migrates). |
| `INIT_PASSWORD` | `${{secret(16, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password required on /install before the first admin account can be created. Read it from this variable. |
| `SECRET_KEY` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Flask signing/encryption key. Shared by API, WebSocket, Worker and Beat. Never change after first boot. |
| `DEPLOY_ENV` | `PRODUCTION` | Deployment environment flag. |
| `LOG_LEVEL` | `INFO` | Log verbosity (DEBUG, INFO, WARNING, ERROR). |
| `DIFY_PUBLIC_URL` | `https://${{Gateway.RAILWAY_PUBLIC_DOMAIN}}` | Public base URL of this Dify instance (the Gateway). Change here when you add a custom domain. |
| `CONSOLE_API_URL` | `${{DIFY_PUBLIC_URL}}` | Public URL of the console API (same origin via Gateway). |
| `CONSOLE_WEB_URL` | `${{DIFY_PUBLIC_URL}}` | Public URL of the console web UI. |
| `SERVICE_API_URL` | `${{DIFY_PUBLIC_URL}}` | Base URL shown for the Service API (/v1). |
| `APP_API_URL` | `${{DIFY_PUBLIC_URL}}` | Public URL of the web-app API. |
| `APP_WEB_URL` | `${{DIFY_PUBLIC_URL}}` | Public URL of published web apps. |
| `FILES_URL` | `${{DIFY_PUBLIC_URL}}` | Public prefix for signed file preview/download links. |
| `TRIGGER_URL` | `${{DIFY_PUBLIC_URL}}` | Public prefix for workflow trigger webhooks. |
| `INTERNAL_FILES_URL` | `http://${{API.RAILWAY_PRIVATE_DOMAIN}}:5001` | Private URL used by Plugin Daemon and Agent services to fetch files. |
| `ENDPOINT_URL_TEMPLATE` | `${{DIFY_PUBLIC_URL}}/e/{hook_id}` | Public URL template for plugin endpoints (routed by the Gateway to Plugin Daemon). |
| `CONSOLE_CORS_ALLOW_ORIGINS` | `${{DIFY_PUBLIC_URL}}` | Allowed origins for the console API (same origin by default). |
| `WEB_API_CORS_ALLOW_ORIGINS` | `*` | Allowed origins for the public web-app API (embeds need *). |
| `ENABLE_COLLABORATION_MODE` | `true` | Real-time collaborative workflow editing via the API WebSocket service. |
| `DB_TYPE` | `postgresql` | Metadata database type. |
| `DB_HOST` | `${{Postgres.PGHOST}}` | Postgres private host. |
| `DB_PORT` | `${{Postgres.PGPORT}}` | Postgres port. |
| `DB_USERNAME` | `${{Postgres.PGUSER}}` | Postgres user. |
| `DB_PASSWORD` | `${{Postgres.PGPASSWORD}}` | Postgres password. |
| `DB_DATABASE` | `${{Postgres.PGDATABASE}}` | Dify metadata database. |
| `SQLALCHEMY_POOL_SIZE` | `10` | DB pool size per process (kept below Postgres' default 100 connections across all services). |
| `SQLALCHEMY_MAX_OVERFLOW` | `5` | Extra DB connections allowed above the pool size. |
| `SQLALCHEMY_POOL_PRE_PING` | `true` | Validate pooled connections before use (survives idle network resets). |
| `SQLALCHEMY_POOL_RECYCLE` | `3600` | Recycle DB connections after N seconds. |
| `REDIS_HOST` | `${{Redis.REDISHOST}}` | Redis private host. |
| `REDIS_PORT` | `${{Redis.REDISPORT}}` | Redis port. |
| `REDIS_USERNAME` | `${{Redis.REDISUSER}}` | Redis user. |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password. |
| `REDIS_DB` | `0` | Redis DB index for cache/locks. |
| `CELERY_BROKER_URL` | `redis://${{Redis.REDISUSER}}:${{Redis.REDIS_PASSWORD}}@${{Redis.REDISHOST}}:${{Redis.REDISPORT}}/1` | Celery broker (Redis DB 1). |
| `CELERY_BACKEND` | `redis` | Celery result backend. |
| `STORAGE_TYPE` | `s3` | File storage backend: Railway Bucket via the S3 API. |
| `S3_ENDPOINT` | `${{Bucket.ENDPOINT}}` | Railway Bucket S3 endpoint. |
| `S3_REGION` | `${{Bucket.REGION}}` | Railway Bucket region. |
| `S3_BUCKET_NAME` | `${{Bucket.BUCKET}}` | Railway Bucket name (S3 API name). |
| `S3_ACCESS_KEY` | `${{Bucket.ACCESS_KEY_ID}}` | Railway Bucket access key. |
| `S3_SECRET_KEY` | `${{Bucket.SECRET_ACCESS_KEY}}` | Railway Bucket secret key. |
| `S3_ADDRESS_STYLE` | `virtual` | S3 addressing style. Railway Buckets use virtual-hosted style; set 'path' only if the bucket's Credentials tab says so. |
| `S3_USE_AWS_MANAGED_IAM` | `false` | Use static keys, not AWS IAM roles. |
| `VECTOR_STORE` | `weaviate` | Vector database used for knowledge bases. |
| `WEAVIATE_ENDPOINT` | `http://${{Weaviate.RAILWAY_PRIVATE_DOMAIN}}:8080` | Weaviate REST endpoint (private). |
| `WEAVIATE_GRPC_ENDPOINT` | `grpc://${{Weaviate.RAILWAY_PRIVATE_DOMAIN}}:50051` | Weaviate gRPC endpoint (private). |
| `WEAVIATE_API_KEY` | `${{Weaviate.AUTHENTICATION_APIKEY_ALLOWED_KEYS}}` | Weaviate API key. |
| `CODE_EXECUTION_ENDPOINT` | `http://${{Sandbox.RAILWAY_PRIVATE_DOMAIN}}:8194` | Code sandbox endpoint (private). |
| `CODE_EXECUTION_API_KEY` | `${{Sandbox.API_KEY}}` | Code sandbox API key. |
| `SSRF_PROXY_HTTP_URL` | `http://${{SSRF Proxy.RAILWAY_PRIVATE_DOMAIN}}:3128` | SSRF proxy for outbound HTTP from workflows/tools. |
| `SSRF_PROXY_HTTPS_URL` | `http://${{SSRF Proxy.RAILWAY_PRIVATE_DOMAIN}}:3128` | SSRF proxy for outbound HTTPS from workflows/tools. |
| `PLUGIN_DAEMON_URL` | `http://${{Plugin Daemon.RAILWAY_PRIVATE_DOMAIN}}:5002` | Plugin Daemon endpoint (private). |
| `PLUGIN_DAEMON_KEY` | `${{Plugin Daemon.SERVER_KEY}}` | Key the API uses to call Plugin Daemon. |
| `INNER_API_KEY_FOR_PLUGIN` | `${{Plugin Daemon.DIFY_INNER_API_KEY}}` | Key Plugin Daemon / Agent Backend use to call the API's inner endpoints. |
| `PLUGIN_MAX_PACKAGE_SIZE` | `52428800` | Max plugin package size in bytes. |
| `PLUGIN_DAEMON_TIMEOUT` | `600.0` | Timeout (s) for plugin invocations. |
| `MARKETPLACE_ENABLED` | `true` | Enable the Dify plugin marketplace. |
| `MARKETPLACE_API_URL` | `https://marketplace.dify.ai` | Plugin marketplace API. |
| `AGENT_BACKEND_BASE_URL` | `http://${{Agent Backend.RAILWAY_PRIVATE_DOMAIN}}:5050` | Dify Agent backend endpoint (private). |
| `AGENT_BACKEND_API_TOKEN` | `${{Agent Backend.DIFY_AGENT_API_TOKEN}}` | Bearer token for the Agent backend control plane. |

### API WebSocket

- **Source:** Docker image `langgenius/dify-api:1.17.1`
- **Start command:** image default
- **Healthcheck:** `/health` (timeout 600 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `MODE` | `api` | dify-api run mode. |
| `PORT` | `5001` | Port Railway health-checks and routes to. |
| `DIFY_BIND_ADDRESS` | `[::]` | Bind on IPv4+IPv6 so the private network can reach it. |
| `DIFY_PORT` | `5001` | Gunicorn listen port. |
| `SERVER_WORKER_AMOUNT` | `1` | Gunicorn worker processes (raise with more RAM/CPU). |
| `SERVER_WORKER_CLASS` | `geventwebsocket.gunicorn.workers.GeventWebSocketWorker` | Gunicorn worker class. |
| `SERVER_WORKER_CONNECTIONS` | `1000` | Concurrent connections per worker. |
| `GUNICORN_TIMEOUT` | `360` | Request timeout in seconds (long streaming responses). |
| `MIGRATION_ENABLED` | `false` | Migrations are run by the API service only. |
| `SECRET_KEY` | `${{API.SECRET_KEY}}` | Flask signing/encryption key. Shared by API, WebSocket, Worker and Beat. Never change after first boot. |
| `DEPLOY_ENV` | `${{API.DEPLOY_ENV}}` | Deployment environment flag. |
| `LOG_LEVEL` | `${{API.LOG_LEVEL}}` | Log verbosity (DEBUG, INFO, WARNING, ERROR). |
| `DIFY_PUBLIC_URL` | `${{API.DIFY_PUBLIC_URL}}` | Public base URL of this Dify instance (the Gateway). Change here when you add a custom domain. |
| `CONSOLE_API_URL` | `${{API.CONSOLE_API_URL}}` | Public URL of the console API (same origin via Gateway). |
| `CONSOLE_WEB_URL` | `${{API.CONSOLE_WEB_URL}}` | Public URL of the console web UI. |
| `SERVICE_API_URL` | `${{API.SERVICE_API_URL}}` | Base URL shown for the Service API (/v1). |
| `APP_API_URL` | `${{API.APP_API_URL}}` | Public URL of the web-app API. |
| `APP_WEB_URL` | `${{API.APP_WEB_URL}}` | Public URL of published web apps. |
| `FILES_URL` | `${{API.FILES_URL}}` | Public prefix for signed file preview/download links. |
| `TRIGGER_URL` | `${{API.TRIGGER_URL}}` | Public prefix for workflow trigger webhooks. |
| `INTERNAL_FILES_URL` | `${{API.INTERNAL_FILES_URL}}` | Private URL used by Plugin Daemon and Agent services to fetch files. |
| `ENDPOINT_URL_TEMPLATE` | `${{API.ENDPOINT_URL_TEMPLATE}}` | Public URL template for plugin endpoints (routed by the Gateway to Plugin Daemon). |
| `CONSOLE_CORS_ALLOW_ORIGINS` | `${{API.CONSOLE_CORS_ALLOW_ORIGINS}}` | Allowed origins for the console API (same origin by default). |
| `WEB_API_CORS_ALLOW_ORIGINS` | `${{API.WEB_API_CORS_ALLOW_ORIGINS}}` | Allowed origins for the public web-app API (embeds need *). |
| `ENABLE_COLLABORATION_MODE` | `${{API.ENABLE_COLLABORATION_MODE}}` | Real-time collaborative workflow editing via the API WebSocket service. |
| `DB_TYPE` | `${{API.DB_TYPE}}` | Metadata database type. |
| `DB_HOST` | `${{API.DB_HOST}}` | Postgres private host. |
| `DB_PORT` | `${{API.DB_PORT}}` | Postgres port. |
| `DB_USERNAME` | `${{API.DB_USERNAME}}` | Postgres user. |
| `DB_PASSWORD` | `${{API.DB_PASSWORD}}` | Postgres password. |
| `DB_DATABASE` | `${{API.DB_DATABASE}}` | Dify metadata database. |
| `SQLALCHEMY_POOL_SIZE` | `${{API.SQLALCHEMY_POOL_SIZE}}` | DB pool size per process (kept below Postgres' default 100 connections across all services). |
| `SQLALCHEMY_MAX_OVERFLOW` | `${{API.SQLALCHEMY_MAX_OVERFLOW}}` | Extra DB connections allowed above the pool size. |
| `SQLALCHEMY_POOL_PRE_PING` | `${{API.SQLALCHEMY_POOL_PRE_PING}}` | Validate pooled connections before use (survives idle network resets). |
| `SQLALCHEMY_POOL_RECYCLE` | `${{API.SQLALCHEMY_POOL_RECYCLE}}` | Recycle DB connections after N seconds. |
| `REDIS_HOST` | `${{API.REDIS_HOST}}` | Redis private host. |
| `REDIS_PORT` | `${{API.REDIS_PORT}}` | Redis port. |
| `REDIS_USERNAME` | `${{API.REDIS_USERNAME}}` | Redis user. |
| `REDIS_PASSWORD` | `${{API.REDIS_PASSWORD}}` | Redis password. |
| `REDIS_DB` | `${{API.REDIS_DB}}` | Redis DB index for cache/locks. |
| `CELERY_BROKER_URL` | `${{API.CELERY_BROKER_URL}}` | Celery broker (Redis DB 1). |
| `CELERY_BACKEND` | `${{API.CELERY_BACKEND}}` | Celery result backend. |
| `STORAGE_TYPE` | `${{API.STORAGE_TYPE}}` | File storage backend: Railway Bucket via the S3 API. |
| `S3_ENDPOINT` | `${{API.S3_ENDPOINT}}` | Railway Bucket S3 endpoint. |
| `S3_REGION` | `${{API.S3_REGION}}` | Railway Bucket region. |
| `S3_BUCKET_NAME` | `${{API.S3_BUCKET_NAME}}` | Railway Bucket name (S3 API name). |
| `S3_ACCESS_KEY` | `${{API.S3_ACCESS_KEY}}` | Railway Bucket access key. |
| `S3_SECRET_KEY` | `${{API.S3_SECRET_KEY}}` | Railway Bucket secret key. |
| `S3_ADDRESS_STYLE` | `${{API.S3_ADDRESS_STYLE}}` | S3 addressing style. Railway Buckets use virtual-hosted style; set 'path' only if the bucket's Credentials tab says so. |
| `S3_USE_AWS_MANAGED_IAM` | `${{API.S3_USE_AWS_MANAGED_IAM}}` | Use static keys, not AWS IAM roles. |
| `VECTOR_STORE` | `${{API.VECTOR_STORE}}` | Vector database used for knowledge bases. |
| `WEAVIATE_ENDPOINT` | `${{API.WEAVIATE_ENDPOINT}}` | Weaviate REST endpoint (private). |
| `WEAVIATE_GRPC_ENDPOINT` | `${{API.WEAVIATE_GRPC_ENDPOINT}}` | Weaviate gRPC endpoint (private). |
| `WEAVIATE_API_KEY` | `${{API.WEAVIATE_API_KEY}}` | Weaviate API key. |
| `CODE_EXECUTION_ENDPOINT` | `${{API.CODE_EXECUTION_ENDPOINT}}` | Code sandbox endpoint (private). |
| `CODE_EXECUTION_API_KEY` | `${{API.CODE_EXECUTION_API_KEY}}` | Code sandbox API key. |
| `SSRF_PROXY_HTTP_URL` | `${{API.SSRF_PROXY_HTTP_URL}}` | SSRF proxy for outbound HTTP from workflows/tools. |
| `SSRF_PROXY_HTTPS_URL` | `${{API.SSRF_PROXY_HTTPS_URL}}` | SSRF proxy for outbound HTTPS from workflows/tools. |
| `PLUGIN_DAEMON_URL` | `${{API.PLUGIN_DAEMON_URL}}` | Plugin Daemon endpoint (private). |
| `PLUGIN_DAEMON_KEY` | `${{API.PLUGIN_DAEMON_KEY}}` | Key the API uses to call Plugin Daemon. |
| `INNER_API_KEY_FOR_PLUGIN` | `${{API.INNER_API_KEY_FOR_PLUGIN}}` | Key Plugin Daemon / Agent Backend use to call the API's inner endpoints. |
| `PLUGIN_MAX_PACKAGE_SIZE` | `${{API.PLUGIN_MAX_PACKAGE_SIZE}}` | Max plugin package size in bytes. |
| `PLUGIN_DAEMON_TIMEOUT` | `${{API.PLUGIN_DAEMON_TIMEOUT}}` | Timeout (s) for plugin invocations. |
| `MARKETPLACE_ENABLED` | `${{API.MARKETPLACE_ENABLED}}` | Enable the Dify plugin marketplace. |
| `MARKETPLACE_API_URL` | `${{API.MARKETPLACE_API_URL}}` | Plugin marketplace API. |
| `AGENT_BACKEND_BASE_URL` | `${{API.AGENT_BACKEND_BASE_URL}}` | Dify Agent backend endpoint (private). |
| `AGENT_BACKEND_API_TOKEN` | `${{API.AGENT_BACKEND_API_TOKEN}}` | Bearer token for the Agent backend control plane. |

### Worker

- **Source:** Docker image `langgenius/dify-api:1.17.1`
- **Start command:** image default
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `MODE` | `worker` | dify-api run mode: Celery worker for all queues. |
| `MIGRATION_ENABLED` | `false` | Migrations are run by the API service only. |
| `CELERY_WORKER_AMOUNT` | `4` | Celery concurrency (gevent greenlets) per replica. |
| `CELERY_AUTO_SCALE` | `false` | Autoscale Celery concurrency by CPU count. |
| `SECRET_KEY` | `${{API.SECRET_KEY}}` | Flask signing/encryption key. Shared by API, WebSocket, Worker and Beat. Never change after first boot. |
| `DEPLOY_ENV` | `${{API.DEPLOY_ENV}}` | Deployment environment flag. |
| `LOG_LEVEL` | `${{API.LOG_LEVEL}}` | Log verbosity (DEBUG, INFO, WARNING, ERROR). |
| `DIFY_PUBLIC_URL` | `${{API.DIFY_PUBLIC_URL}}` | Public base URL of this Dify instance (the Gateway). Change here when you add a custom domain. |
| `CONSOLE_API_URL` | `${{API.CONSOLE_API_URL}}` | Public URL of the console API (same origin via Gateway). |
| `CONSOLE_WEB_URL` | `${{API.CONSOLE_WEB_URL}}` | Public URL of the console web UI. |
| `SERVICE_API_URL` | `${{API.SERVICE_API_URL}}` | Base URL shown for the Service API (/v1). |
| `APP_API_URL` | `${{API.APP_API_URL}}` | Public URL of the web-app API. |
| `APP_WEB_URL` | `${{API.APP_WEB_URL}}` | Public URL of published web apps. |
| `FILES_URL` | `${{API.FILES_URL}}` | Public prefix for signed file preview/download links. |
| `TRIGGER_URL` | `${{API.TRIGGER_URL}}` | Public prefix for workflow trigger webhooks. |
| `INTERNAL_FILES_URL` | `${{API.INTERNAL_FILES_URL}}` | Private URL used by Plugin Daemon and Agent services to fetch files. |
| `ENDPOINT_URL_TEMPLATE` | `${{API.ENDPOINT_URL_TEMPLATE}}` | Public URL template for plugin endpoints (routed by the Gateway to Plugin Daemon). |
| `CONSOLE_CORS_ALLOW_ORIGINS` | `${{API.CONSOLE_CORS_ALLOW_ORIGINS}}` | Allowed origins for the console API (same origin by default). |
| `WEB_API_CORS_ALLOW_ORIGINS` | `${{API.WEB_API_CORS_ALLOW_ORIGINS}}` | Allowed origins for the public web-app API (embeds need *). |
| `ENABLE_COLLABORATION_MODE` | `${{API.ENABLE_COLLABORATION_MODE}}` | Real-time collaborative workflow editing via the API WebSocket service. |
| `DB_TYPE` | `${{API.DB_TYPE}}` | Metadata database type. |
| `DB_HOST` | `${{API.DB_HOST}}` | Postgres private host. |
| `DB_PORT` | `${{API.DB_PORT}}` | Postgres port. |
| `DB_USERNAME` | `${{API.DB_USERNAME}}` | Postgres user. |
| `DB_PASSWORD` | `${{API.DB_PASSWORD}}` | Postgres password. |
| `DB_DATABASE` | `${{API.DB_DATABASE}}` | Dify metadata database. |
| `SQLALCHEMY_POOL_SIZE` | `${{API.SQLALCHEMY_POOL_SIZE}}` | DB pool size per process (kept below Postgres' default 100 connections across all services). |
| `SQLALCHEMY_MAX_OVERFLOW` | `${{API.SQLALCHEMY_MAX_OVERFLOW}}` | Extra DB connections allowed above the pool size. |
| `SQLALCHEMY_POOL_PRE_PING` | `${{API.SQLALCHEMY_POOL_PRE_PING}}` | Validate pooled connections before use (survives idle network resets). |
| `SQLALCHEMY_POOL_RECYCLE` | `${{API.SQLALCHEMY_POOL_RECYCLE}}` | Recycle DB connections after N seconds. |
| `REDIS_HOST` | `${{API.REDIS_HOST}}` | Redis private host. |
| `REDIS_PORT` | `${{API.REDIS_PORT}}` | Redis port. |
| `REDIS_USERNAME` | `${{API.REDIS_USERNAME}}` | Redis user. |
| `REDIS_PASSWORD` | `${{API.REDIS_PASSWORD}}` | Redis password. |
| `REDIS_DB` | `${{API.REDIS_DB}}` | Redis DB index for cache/locks. |
| `CELERY_BROKER_URL` | `${{API.CELERY_BROKER_URL}}` | Celery broker (Redis DB 1). |
| `CELERY_BACKEND` | `${{API.CELERY_BACKEND}}` | Celery result backend. |
| `STORAGE_TYPE` | `${{API.STORAGE_TYPE}}` | File storage backend: Railway Bucket via the S3 API. |
| `S3_ENDPOINT` | `${{API.S3_ENDPOINT}}` | Railway Bucket S3 endpoint. |
| `S3_REGION` | `${{API.S3_REGION}}` | Railway Bucket region. |
| `S3_BUCKET_NAME` | `${{API.S3_BUCKET_NAME}}` | Railway Bucket name (S3 API name). |
| `S3_ACCESS_KEY` | `${{API.S3_ACCESS_KEY}}` | Railway Bucket access key. |
| `S3_SECRET_KEY` | `${{API.S3_SECRET_KEY}}` | Railway Bucket secret key. |
| `S3_ADDRESS_STYLE` | `${{API.S3_ADDRESS_STYLE}}` | S3 addressing style. Railway Buckets use virtual-hosted style; set 'path' only if the bucket's Credentials tab says so. |
| `S3_USE_AWS_MANAGED_IAM` | `${{API.S3_USE_AWS_MANAGED_IAM}}` | Use static keys, not AWS IAM roles. |
| `VECTOR_STORE` | `${{API.VECTOR_STORE}}` | Vector database used for knowledge bases. |
| `WEAVIATE_ENDPOINT` | `${{API.WEAVIATE_ENDPOINT}}` | Weaviate REST endpoint (private). |
| `WEAVIATE_GRPC_ENDPOINT` | `${{API.WEAVIATE_GRPC_ENDPOINT}}` | Weaviate gRPC endpoint (private). |
| `WEAVIATE_API_KEY` | `${{API.WEAVIATE_API_KEY}}` | Weaviate API key. |
| `CODE_EXECUTION_ENDPOINT` | `${{API.CODE_EXECUTION_ENDPOINT}}` | Code sandbox endpoint (private). |
| `CODE_EXECUTION_API_KEY` | `${{API.CODE_EXECUTION_API_KEY}}` | Code sandbox API key. |
| `SSRF_PROXY_HTTP_URL` | `${{API.SSRF_PROXY_HTTP_URL}}` | SSRF proxy for outbound HTTP from workflows/tools. |
| `SSRF_PROXY_HTTPS_URL` | `${{API.SSRF_PROXY_HTTPS_URL}}` | SSRF proxy for outbound HTTPS from workflows/tools. |
| `PLUGIN_DAEMON_URL` | `${{API.PLUGIN_DAEMON_URL}}` | Plugin Daemon endpoint (private). |
| `PLUGIN_DAEMON_KEY` | `${{API.PLUGIN_DAEMON_KEY}}` | Key the API uses to call Plugin Daemon. |
| `INNER_API_KEY_FOR_PLUGIN` | `${{API.INNER_API_KEY_FOR_PLUGIN}}` | Key Plugin Daemon / Agent Backend use to call the API's inner endpoints. |
| `PLUGIN_MAX_PACKAGE_SIZE` | `${{API.PLUGIN_MAX_PACKAGE_SIZE}}` | Max plugin package size in bytes. |
| `PLUGIN_DAEMON_TIMEOUT` | `${{API.PLUGIN_DAEMON_TIMEOUT}}` | Timeout (s) for plugin invocations. |
| `MARKETPLACE_ENABLED` | `${{API.MARKETPLACE_ENABLED}}` | Enable the Dify plugin marketplace. |
| `MARKETPLACE_API_URL` | `${{API.MARKETPLACE_API_URL}}` | Plugin marketplace API. |
| `AGENT_BACKEND_BASE_URL` | `${{API.AGENT_BACKEND_BASE_URL}}` | Dify Agent backend endpoint (private). |
| `AGENT_BACKEND_API_TOKEN` | `${{API.AGENT_BACKEND_API_TOKEN}}` | Bearer token for the Agent backend control plane. |

### Worker Beat

- **Source:** Docker image `langgenius/dify-api:1.17.1`
- **Start command:** image default
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `MODE` | `beat` | dify-api run mode: Celery beat scheduler (run exactly one). |
| `MIGRATION_ENABLED` | `false` | Migrations are run by the API service only. |
| `SECRET_KEY` | `${{API.SECRET_KEY}}` | Flask signing/encryption key. Shared by API, WebSocket, Worker and Beat. Never change after first boot. |
| `DEPLOY_ENV` | `${{API.DEPLOY_ENV}}` | Deployment environment flag. |
| `LOG_LEVEL` | `${{API.LOG_LEVEL}}` | Log verbosity (DEBUG, INFO, WARNING, ERROR). |
| `DIFY_PUBLIC_URL` | `${{API.DIFY_PUBLIC_URL}}` | Public base URL of this Dify instance (the Gateway). Change here when you add a custom domain. |
| `CONSOLE_API_URL` | `${{API.CONSOLE_API_URL}}` | Public URL of the console API (same origin via Gateway). |
| `CONSOLE_WEB_URL` | `${{API.CONSOLE_WEB_URL}}` | Public URL of the console web UI. |
| `SERVICE_API_URL` | `${{API.SERVICE_API_URL}}` | Base URL shown for the Service API (/v1). |
| `APP_API_URL` | `${{API.APP_API_URL}}` | Public URL of the web-app API. |
| `APP_WEB_URL` | `${{API.APP_WEB_URL}}` | Public URL of published web apps. |
| `FILES_URL` | `${{API.FILES_URL}}` | Public prefix for signed file preview/download links. |
| `TRIGGER_URL` | `${{API.TRIGGER_URL}}` | Public prefix for workflow trigger webhooks. |
| `INTERNAL_FILES_URL` | `${{API.INTERNAL_FILES_URL}}` | Private URL used by Plugin Daemon and Agent services to fetch files. |
| `ENDPOINT_URL_TEMPLATE` | `${{API.ENDPOINT_URL_TEMPLATE}}` | Public URL template for plugin endpoints (routed by the Gateway to Plugin Daemon). |
| `CONSOLE_CORS_ALLOW_ORIGINS` | `${{API.CONSOLE_CORS_ALLOW_ORIGINS}}` | Allowed origins for the console API (same origin by default). |
| `WEB_API_CORS_ALLOW_ORIGINS` | `${{API.WEB_API_CORS_ALLOW_ORIGINS}}` | Allowed origins for the public web-app API (embeds need *). |
| `ENABLE_COLLABORATION_MODE` | `${{API.ENABLE_COLLABORATION_MODE}}` | Real-time collaborative workflow editing via the API WebSocket service. |
| `DB_TYPE` | `${{API.DB_TYPE}}` | Metadata database type. |
| `DB_HOST` | `${{API.DB_HOST}}` | Postgres private host. |
| `DB_PORT` | `${{API.DB_PORT}}` | Postgres port. |
| `DB_USERNAME` | `${{API.DB_USERNAME}}` | Postgres user. |
| `DB_PASSWORD` | `${{API.DB_PASSWORD}}` | Postgres password. |
| `DB_DATABASE` | `${{API.DB_DATABASE}}` | Dify metadata database. |
| `SQLALCHEMY_POOL_SIZE` | `${{API.SQLALCHEMY_POOL_SIZE}}` | DB pool size per process (kept below Postgres' default 100 connections across all services). |
| `SQLALCHEMY_MAX_OVERFLOW` | `${{API.SQLALCHEMY_MAX_OVERFLOW}}` | Extra DB connections allowed above the pool size. |
| `SQLALCHEMY_POOL_PRE_PING` | `${{API.SQLALCHEMY_POOL_PRE_PING}}` | Validate pooled connections before use (survives idle network resets). |
| `SQLALCHEMY_POOL_RECYCLE` | `${{API.SQLALCHEMY_POOL_RECYCLE}}` | Recycle DB connections after N seconds. |
| `REDIS_HOST` | `${{API.REDIS_HOST}}` | Redis private host. |
| `REDIS_PORT` | `${{API.REDIS_PORT}}` | Redis port. |
| `REDIS_USERNAME` | `${{API.REDIS_USERNAME}}` | Redis user. |
| `REDIS_PASSWORD` | `${{API.REDIS_PASSWORD}}` | Redis password. |
| `REDIS_DB` | `${{API.REDIS_DB}}` | Redis DB index for cache/locks. |
| `CELERY_BROKER_URL` | `${{API.CELERY_BROKER_URL}}` | Celery broker (Redis DB 1). |
| `CELERY_BACKEND` | `${{API.CELERY_BACKEND}}` | Celery result backend. |
| `STORAGE_TYPE` | `${{API.STORAGE_TYPE}}` | File storage backend: Railway Bucket via the S3 API. |
| `S3_ENDPOINT` | `${{API.S3_ENDPOINT}}` | Railway Bucket S3 endpoint. |
| `S3_REGION` | `${{API.S3_REGION}}` | Railway Bucket region. |
| `S3_BUCKET_NAME` | `${{API.S3_BUCKET_NAME}}` | Railway Bucket name (S3 API name). |
| `S3_ACCESS_KEY` | `${{API.S3_ACCESS_KEY}}` | Railway Bucket access key. |
| `S3_SECRET_KEY` | `${{API.S3_SECRET_KEY}}` | Railway Bucket secret key. |
| `S3_ADDRESS_STYLE` | `${{API.S3_ADDRESS_STYLE}}` | S3 addressing style. Railway Buckets use virtual-hosted style; set 'path' only if the bucket's Credentials tab says so. |
| `S3_USE_AWS_MANAGED_IAM` | `${{API.S3_USE_AWS_MANAGED_IAM}}` | Use static keys, not AWS IAM roles. |
| `VECTOR_STORE` | `${{API.VECTOR_STORE}}` | Vector database used for knowledge bases. |
| `WEAVIATE_ENDPOINT` | `${{API.WEAVIATE_ENDPOINT}}` | Weaviate REST endpoint (private). |
| `WEAVIATE_GRPC_ENDPOINT` | `${{API.WEAVIATE_GRPC_ENDPOINT}}` | Weaviate gRPC endpoint (private). |
| `WEAVIATE_API_KEY` | `${{API.WEAVIATE_API_KEY}}` | Weaviate API key. |
| `CODE_EXECUTION_ENDPOINT` | `${{API.CODE_EXECUTION_ENDPOINT}}` | Code sandbox endpoint (private). |
| `CODE_EXECUTION_API_KEY` | `${{API.CODE_EXECUTION_API_KEY}}` | Code sandbox API key. |
| `SSRF_PROXY_HTTP_URL` | `${{API.SSRF_PROXY_HTTP_URL}}` | SSRF proxy for outbound HTTP from workflows/tools. |
| `SSRF_PROXY_HTTPS_URL` | `${{API.SSRF_PROXY_HTTPS_URL}}` | SSRF proxy for outbound HTTPS from workflows/tools. |
| `PLUGIN_DAEMON_URL` | `${{API.PLUGIN_DAEMON_URL}}` | Plugin Daemon endpoint (private). |
| `PLUGIN_DAEMON_KEY` | `${{API.PLUGIN_DAEMON_KEY}}` | Key the API uses to call Plugin Daemon. |
| `INNER_API_KEY_FOR_PLUGIN` | `${{API.INNER_API_KEY_FOR_PLUGIN}}` | Key Plugin Daemon / Agent Backend use to call the API's inner endpoints. |
| `PLUGIN_MAX_PACKAGE_SIZE` | `${{API.PLUGIN_MAX_PACKAGE_SIZE}}` | Max plugin package size in bytes. |
| `PLUGIN_DAEMON_TIMEOUT` | `${{API.PLUGIN_DAEMON_TIMEOUT}}` | Timeout (s) for plugin invocations. |
| `MARKETPLACE_ENABLED` | `${{API.MARKETPLACE_ENABLED}}` | Enable the Dify plugin marketplace. |
| `MARKETPLACE_API_URL` | `${{API.MARKETPLACE_API_URL}}` | Plugin marketplace API. |
| `AGENT_BACKEND_BASE_URL` | `${{API.AGENT_BACKEND_BASE_URL}}` | Dify Agent backend endpoint (private). |
| `AGENT_BACKEND_API_TOKEN` | `${{API.AGENT_BACKEND_API_TOKEN}}` | Bearer token for the Agent backend control plane. |

### Plugin Daemon

- **Source:** Docker image `langgenius/dify-plugin-daemon:0.6.10-local`
- **Start command:** image default
- **Healthcheck:** `/health/check` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/app/storage`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `5002` | Port Railway health-checks. |
| `SERVER_HOST` | `[::]` | Listen on IPv4+IPv6. |
| `SERVER_PORT` | `5002` | Plugin Daemon HTTP port. |
| `SERVER_KEY` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Key the API presents to Plugin Daemon. |
| `DIFY_INNER_API_URL` | `http://${{API.RAILWAY_PRIVATE_DOMAIN}}:5001` | API inner endpoint (private). |
| `DIFY_INNER_API_KEY` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Key Plugin Daemon presents to the API inner endpoints. |
| `DB_TYPE` | `postgresql` | Database type. |
| `DB_HOST` | `${{Postgres.PGHOST}}` | Postgres private host. |
| `DB_PORT` | `${{Postgres.PGPORT}}` | Postgres port. |
| `DB_USERNAME` | `${{Postgres.PGUSER}}` | Postgres user. |
| `DB_PASSWORD` | `${{Postgres.PGPASSWORD}}` | Postgres password. |
| `DB_DATABASE` | `dify_plugin` | Plugin database (created automatically on first boot). |
| `DB_SSL_MODE` | `disable` | Private network; TLS not required. |
| `DB_MAX_OPEN_CONNS` | `20` | Max DB connections. |
| `DB_MAX_IDLE_CONNS` | `5` | Idle DB connections kept open. |
| `REDIS_HOST` | `${{Redis.REDISHOST}}` | Redis private host. |
| `REDIS_PORT` | `${{Redis.REDISPORT}}` | Redis port. |
| `REDIS_USERNAME` | `${{Redis.REDISUSER}}` | Redis user. |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password. |
| `REDIS_DB` | `0` | Redis DB index (keys are prefixed). |
| `PLUGIN_STORAGE_TYPE` | `local` | Plugin packages are kept on this service's volume. |
| `PLUGIN_STORAGE_LOCAL_ROOT` | `/app/storage` | Storage root (the volume). |
| `PLUGIN_WORKING_PATH` | `/app/storage/cwd` | Where installed plugins run (Python envs). |
| `PLUGIN_INSTALLED_PATH` | `plugin` | Installed plugins sub-directory. |
| `PLUGIN_PACKAGE_CACHE_PATH` | `plugin_packages` | Package cache sub-directory. |
| `PLUGIN_MEDIA_CACHE_PATH` | `assets` | Plugin asset cache sub-directory. |
| `MAX_PLUGIN_PACKAGE_SIZE` | `52428800` | Max plugin package size in bytes. |
| `PLUGIN_MAX_EXECUTION_TIMEOUT` | `600` | Max plugin execution time (s). |
| `PYTHON_ENV_INIT_TIMEOUT` | `120` | Timeout (s) to build a plugin's Python environment. |
| `FORCE_VERIFYING_SIGNATURE` | `true` | Only allow signed marketplace plugins. |
| `PLUGIN_REMOTE_INSTALLING_HOST` | `0.0.0.0` | Remote plugin-debugging listener (needs a TCP proxy on 5003 to be used). |
| `PLUGIN_REMOTE_INSTALLING_PORT` | `5003` | Remote plugin-debugging port. |
| `PPROF_ENABLED` | `false` | Go profiler endpoint. |
| `PIP_MIRROR_URL` | *(empty)* | Optional PyPI mirror for plugin installs. |

### Sandbox

- **Source:** Docker image `langgenius/dify-sandbox:0.2.15`
- **Start command:** image default
- **Healthcheck:** `/health` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/dependencies`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8194` | Port Railway health-checks. |
| `SANDBOX_PORT` | `8194` | Sandbox listen port. |
| `API_KEY` | `${{secret(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Key the API uses to call the code sandbox. |
| `GIN_MODE` | `release` | Go web framework mode. |
| `WORKER_TIMEOUT` | `15` | Max code execution time (s). |
| `ENABLE_NETWORK` | `true` | Allow sandboxed code to make network calls (through the SSRF proxy). |
| `HTTP_PROXY` | `http://${{SSRF Proxy.RAILWAY_PRIVATE_DOMAIN}}:3128` | Egress via SSRF proxy. |
| `HTTPS_PROXY` | `http://${{SSRF Proxy.RAILWAY_PRIVATE_DOMAIN}}:3128` | Egress via SSRF proxy. |
| `PIP_MIRROR_URL` | *(empty)* | Optional PyPI mirror for extra Python packages. |

### SSRF Proxy

- **Source:** GitHub repo `baranberkay96/dify-railway`, root directory `/services/ssrf-proxy` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `SSRF_PROXY_MODE` | `default` | Policy: default = Dify egress proxy. |
| `HTTP_PORT` | `3128` | Squid listen port. |
| `SSRF_PROXY_ALLOW_PRIVATE_IPS` | *(empty)* | Optional comma-separated CIDRs that workflows may reach despite the private-network block. |
| `SSRF_PROXY_ALLOW_PRIVATE_DOMAINS` | *(empty)* | Optional comma-separated domains (e.g. .railway.internal) that workflows may reach. |

### Agent Backend

- **Source:** Docker image `langgenius/dify-agent-backend:1.17.1`
- **Start command:** `uvicorn dify_agent.server.app:app --host :: --port 5050`
- **Healthcheck:** `/docs` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `5050` | Port Railway health-checks. |
| `DIFY_AGENT_API_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer token the API uses for the Agent control plane. |
| `DIFY_AGENT_SERVER_SECRET_KEY` | `${{secret(43, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Root secret (43-char base64url = 32 bytes) for Agent Stub token encryption. |
| `DIFY_AGENT_REDIS_URL` | `redis://${{Redis.REDISUSER}}:${{Redis.REDIS_PASSWORD}}@${{Redis.REDISHOST}}:${{Redis.REDISPORT}}/2` | Agent run store (Redis DB 2). |
| `DIFY_AGENT_PLUGIN_DAEMON_URL` | `http://${{Plugin Daemon.RAILWAY_PRIVATE_DOMAIN}}:5002` | Plugin Daemon endpoint. |
| `DIFY_AGENT_PLUGIN_DAEMON_API_KEY` | `${{Plugin Daemon.SERVER_KEY}}` | Plugin Daemon key. |
| `DIFY_AGENT_INNER_API_URL` | `http://${{API.RAILWAY_PRIVATE_DOMAIN}}:5001` | API inner endpoint. |
| `DIFY_AGENT_INNER_API_KEY` | `${{Plugin Daemon.DIFY_INNER_API_KEY}}` | Must equal the API's INNER_API_KEY_FOR_PLUGIN. |
| `DIFY_AGENT_RUNTIME_BACKEND` | `local` | Sandbox backend: local (Agent Sandbox service) or e2b. |
| `DIFY_AGENT_LOCAL_SANDBOX_ENDPOINT` | `http://${{Agent Sandbox.RAILWAY_PRIVATE_DOMAIN}}:5004` | Agent Sandbox (shellctl) endpoint. |
| `DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Token shared with the Agent Sandbox. |
| `DIFY_AGENT_STUB_API_BASE_URL` | `http://${{RAILWAY_PRIVATE_DOMAIN}}:5050/agent-stub` | Agent Stub URL the sandbox calls (through Agent SSRF Proxy). |
| `DIFY_AGENT_SANDBOX_FILES_BASE_URL` | `http://${{API.RAILWAY_PRIVATE_DOMAIN}}:5001` | API base for sandbox file transfers (/files/*). |
| `DIFY_AGENT_RUN_TIMEOUT_SECONDS` | `3600` | Max agent run time (s). |

### Agent Sandbox

- **Source:** GitHub repo `baranberkay96/dify-railway`, root directory `/services/agent-sandbox` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** `/healthz` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/home/dify`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `5004` | Port Railway health-checks. |
| `SHELLCTL_AUTH_TOKEN` | `${{Agent Backend.DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN}}` | Token the Agent Backend presents. |
| `HTTP_PROXY` | `http://${{Agent SSRF Proxy.RAILWAY_PRIVATE_DOMAIN}}:3128` | Egress via the agent SSRF proxy. |
| `HTTPS_PROXY` | `http://${{Agent SSRF Proxy.RAILWAY_PRIVATE_DOMAIN}}:3128` | Egress via the agent SSRF proxy. |
| `NO_PROXY` | `localhost,127.0.0.1` | Hosts that bypass the proxy. |
| `SHELLCTL_ENABLE_PATH_ISOLATION` | `true` | Landlock path isolation for agent shell jobs. Set false only if jobs fail with Landlock errors. |

### Agent SSRF Proxy

- **Source:** GitHub repo `baranberkay96/dify-railway`, root directory `/services/ssrf-proxy` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `SSRF_PROXY_MODE` | `agent` | Policy: agent = only Agent Stub + API /files/* on the private network, internet otherwise. |
| `HTTP_PORT` | `3128` | Squid listen port. |
| `DIFY_AGENT_BACKEND_HOST` | `${{Agent Backend.RAILWAY_PRIVATE_DOMAIN}}` | Agent Backend private hostname (allowed for /agent-stub/). |
| `DIFY_API_HOST` | `${{API.RAILWAY_PRIVATE_DOMAIN}}` | API private hostname (allowed for /files/). |
| `SSRF_PROXY_ALLOW_PRIVATE_IPS` | *(empty)* | Optional extra private CIDRs the agent may reach. |
| `SSRF_PROXY_ALLOW_PRIVATE_DOMAINS` | *(empty)* | Optional extra private domains the agent may reach. |

### Weaviate

- **Source:** Docker image `semitechnologies/weaviate:1.39.11`
- **Start command:** `/bin/weaviate --host :: --port 8080 --scheme http`
- **Healthcheck:** `/v1/.well-known/ready` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/var/lib/weaviate`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | REST port (gRPC is 50051). |
| `PERSISTENCE_DATA_PATH` | `/var/lib/weaviate` | Data directory (the volume). |
| `CLUSTER_HOSTNAME` | `node1` | Stable node name; do not change after first boot. |
| `QUERY_DEFAULTS_LIMIT` | `25` | Default query limit. |
| `DEFAULT_VECTORIZER_MODULE` | `none` | Dify sends its own embeddings. |
| `AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED` | `false` | Require an API key. |
| `AUTHENTICATION_APIKEY_ENABLED` | `true` | Enable API-key auth. |
| `AUTHENTICATION_APIKEY_ALLOWED_KEYS` | `${{secret(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | API key Dify uses. |
| `AUTHENTICATION_APIKEY_USERS` | `dify` | User mapped to the API key. |
| `AUTHORIZATION_ADMINLIST_ENABLED` | `true` | Admin-list authorization. |
| `AUTHORIZATION_ADMINLIST_USERS` | `${{AUTHENTICATION_APIKEY_USERS}}` | Admin users. |
| `DISABLE_TELEMETRY` | `true` | Disable Weaviate telemetry. |

### Postgres

- **Source:** Docker image `ghcr.io/railwayapp-templates/postgres-ssl:18`
- **Start command:** image default
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/var/lib/postgresql/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1
- **Note:** Copied unchanged from templates/_railway-base/postgres.json

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel |
| `POSTGRES_DB` | `railway` | Default database created when image is started. |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| `POSTGRES_USER` | `postgres` | User to connect to Postgres DB |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password to connect to DB |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down |

### Redis

- **Source:** Docker image `redis:8.2`
- **Start command:** `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH"`
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1
- **Note:** Copied unchanged from templates/_railway-base/redis.json

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service, only resolvable from services in the same environment |
| `REDISPORT` | `6379` | Port that Redis listens on |
| `REDISUSER` | `default` | Username for authenticating with Redis |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis |

### Bucket (Railway Bucket)

- S3-compatible, private. Provides `BUCKET`, `ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`, `REGION`, `ENDPOINT` (referenced as `${{Bucket.ENDPOINT}}` etc.).

## Improvements over market templates

| # | Market issue | This template |
|---|---|---|
| 1 | All three use MinIO (`minio/minio`, `minio/mc`), discontinued; one hardcodes `minioadmin` + a fixed password in the start command | Railway **Bucket** via Dify's S3 driver (`STORAGE_TYPE=s3`, virtual-hosted style); no MinIO, no provisioning job |
| 2 | `TiT2V6` ships upstream's public default secrets (`INNER_API_KEY_FOR_PLUGIN=QaHbTe…`, `SERVER_KEY=lYkiYY…`, serverless connector key) | Every key/password generated with `secret()`; Plugin Daemon ↔ API ↔ Agent keys wired by reference |
| 3 | Web and API on two `*.up.railway.app` domains (cross-site cookies, CORS `*`) | Single-origin Gateway mirroring upstream nginx routes (incl. `/e/`, `/mcp`, `/triggers`, `/socket.io/`) |
| 4 | No `worker_beat` → scheduled tasks (schedule triggers, plugin upgrade checks, cleanups) never run | **Worker Beat** service (`MODE=beat`) |
| 5 | No SSRF proxy → HTTP-request nodes / code sandbox could reach private services | **SSRF Proxy** (Squid) with upstream deny-private policy, used by API, Worker and Sandbox |
| 6 | No collaboration websocket service (upstream default profile `collaboration`) | **API WebSocket** service with the gevent-websocket worker |
| 7 | No Dify Agent stack (new in 1.16/1.17) | **Agent Backend + Agent Sandbox + Agent SSRF Proxy**, Agent V2 enabled in the UI |
| 8 | Unpinned `latest` images (`V1xiql`), Dify 1.13.3 (`dify-ai-workflow`), Weaviate 1.27/1.32, Redis 6 | Dify 1.17.1 set, Weaviate 1.39.11, Railway-base Postgres 18 / Redis 8.2 |
| 9 | `dify-ai-workflow`: no volume on Weaviate or Plugin Daemon (vector index and installed plugins lost on redeploy); nginx `resolver … ipv6=off` breaks on IPv6-only private networks | Volumes on Weaviate, Plugin Daemon, Sandbox, Agent Sandbox; IPv6-aware resolver and `::` binds (API `[::]`, Web `::`, Weaviate `--host ::`, Plugin Daemon `[::]`, Agent services `::`) |
| 10 | Admin bootstrap open: first visitor of `/install` becomes owner | `INIT_PASSWORD` generated; `/install` asks for it first |
| 11 | `V1xiql` needs a separate "Database Provision" job; typo'd references (`${{Redis.REDIS_PASSWORD}}}}`, `${{{PSTGRES_DB}}`) | Dify uses the Railway default DB; Plugin Daemon auto-creates `dify_plugin`; references validated by script |
| 12 | Pools sized for upstream's 200-connection Postgres (30+10 per process) | Pools sized for Railway Postgres (`max_connections=100`): 10+5 per Dify process, 20 for Plugin Daemon; pre-ping enabled |
| 13 | Plugin Daemon remote-debug port exposed publicly via TCP proxy (`TiT2V6`) | Not exposed by default; add a TCP proxy on 5003 only when debugging plugins |

## Scaling

- **Worker**: stateless; raise `numReplicas` (Railway replicas) or `CELERY_WORKER_AMOUNT` for heavy document indexing / workflow load.
- **API**: raise `SERVER_WORKER_AMOUNT` (≈ 1 per vCPU) or add replicas; it holds no local state.
- **Worker Beat**: keep exactly **one** replica (it is the scheduler).
- **Plugin Daemon, Weaviate, Agent Sandbox**: single instance (volumes cannot be shared between replicas).
- When raising replicas/workers, keep total DB connections under 100 (`SQLALCHEMY_POOL_SIZE` + `SQLALCHEMY_MAX_OVERFLOW` per process) or raise Postgres `max_connections`.

## Resource estimate

Prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Estimates from upstream defaults and typical Dify/Celery/Next.js footprints; measure after deploy.

| Service | Idle RAM | Typical RAM | Typical vCPU | Volume |
|---|---|---|---|---|
| Gateway | 20 MB | 30 MB | 0.01 | — |
| Web | 150 MB | 250 MB | 0.02 | — |
| API | 350 MB | 700 MB | 0.10 | — |
| API WebSocket | 300 MB | 400 MB | 0.02 | — |
| Worker | 450 MB | 1.0 GB | 0.15 | — |
| Worker Beat | 200 MB | 250 MB | 0.01 | — |
| Plugin Daemon | 200 MB | 800 MB (≈100–150 MB per running plugin) | 0.05 | ~3 GB |
| Sandbox | 50 MB | 150 MB | 0.02 | ~0.1 GB |
| SSRF Proxy | 30 MB | 60 MB | 0.01 | — |
| Agent Backend | 150 MB | 250 MB | 0.02 | — |
| Agent Sandbox | 50 MB | 300 MB | 0.05 | ~1 GB |
| Agent SSRF Proxy | 30 MB | 50 MB | 0.01 | — |
| Weaviate | 150 MB | 600 MB | 0.05 | ~2 GB |
| Postgres | 80 MB | 250 MB | 0.03 | ~1 GB |
| Redis | 10 MB | 50 MB | 0.01 | ~0.2 GB |
| **Total** | **≈ 2.2 GB** | **≈ 5.1 GB** | **≈ 0.15 idle / 0.55 typical** | **≈ 7.3 GB** |

- **Idle:** 2.2 GB × $10 + 0.15 vCPU × $20 + 7.3 GB × $0.15 ≈ **$26/month**
- **Typical team use:** 5.1 GB × $10 + 0.55 vCPU × $20 + $1.1 ≈ **$64/month**
- Heavy indexing (2 worker replicas, large knowledge bases): ≈ $90–120/month.
- Railway Bucket storage is $0.015/GB-month (10 GB of uploads ≈ $0.15); bucket egress is free.
- **Minimum plan: Hobby.** 15 services exceed what the Trial plan comfortably runs, and Worker / Plugin Daemon can exceed 1 GB under load. Pro recommended for teams (higher per-service limits, more replicas).

## Verification checklist

1. All services show *Active*; healthchecks green: Gateway `/healthz`, Web `/signin`, API and API WebSocket `/health`, Plugin Daemon `/health/check`, Sandbox `/health`, Agent Backend `/docs`, Agent Sandbox `/healthz`, Weaviate `/v1/.well-known/ready`.
2. API logs show `Running migrations` followed by a successful upgrade and Gunicorn start (first boot takes 1–3 min).
3. Open `https://<gateway-domain>/install` → enter `INIT_PASSWORD` (API variables) → create the admin account → you land in the console.
4. Settings → Model Provider: install a provider plugin from the marketplace (proves Plugin Daemon ↔ API keys, marketplace egress, plugin volume).
5. Knowledge → create a knowledge base, upload a PDF → document reaches *Available* (proves Worker, Bucket upload, Weaviate indexing).
6. Create a workflow with a **Code** node (`return {"x": 1}`) and an **HTTP Request** node to `https://httpbin.org/get` → both succeed (Sandbox + SSRF Proxy). An HTTP Request to `http://postgres.railway.internal:5432` must be **blocked**.
7. Open the same workflow in two browser tabs → collaborators' cursors/edits appear (API WebSocket via `/socket.io/`).
8. Create an Agent (v2), publish it, and ask it to run `uname -a` in its shell → answer returned (Agent Backend ↔ Agent Sandbox; Landlock check).
9. Publish a chat app and call `POST https://<gateway-domain>/v1/chat-messages` with its API key.
10. Redeploy API, Plugin Daemon and Weaviate → installed plugins, knowledge bases and uploaded files are still there.
11. Worker Beat logs show `beat: Starting...` and periodic task dispatches.

## Open questions

- **Not deployed yet**: this spec was verified against upstream files, not on a live Railway project. Run the checklist above on first deploy.
- **Agent Sandbox isolation**: upstream keeps `local_sandbox` on Docker networks with no route to `api`; Railway's private network is flat, so agent shell jobs could open direct connections to other services (all of which still require their own keys/passwords). The HTTP(S) proxy policy is enforced only for proxy-aware tools. For untrusted agent users consider the E2B backend (`DIFY_AGENT_RUNTIME_BACKEND=e2b` + `DIFY_AGENT_E2B_API_KEY`) and delete the Agent Sandbox / Agent SSRF Proxy services.
- **Landlock on Railway**: shellctl applies Landlock V1 without a best-effort fallback. If agent jobs fail with a Landlock error, set `SHELLCTL_ENABLE_PATH_ISOLATION=false` on Agent Sandbox (weaker isolation).
- **Bucket addressing**: buckets created before Railway's virtual-hosted switch need `S3_ADDRESS_STYLE=path` (check the bucket's Credentials tab).
- **Railway start command semantics**: Agent Backend and Weaviate use a start command that includes the full binary path, assuming Railway replaces both ENTRYPOINT and CMD.
- **Squid on Railway IPv4 ranges**: client ACL covers `10/8`, `100.64/10`, RFC1918 and `fc00::/7`. If proxied requests are denied with `403` from Squid, check the source address in the Squid access log and extend `client_localnet`.
- **Dify license**: Dify's Open Source License forbids operating a multi-tenant (multi-workspace for third parties) service and removing the console logo/copyright without a commercial license. Single-organisation self-hosting is fine. Mentioned in README.
- **Healthcheck for Web** uses `/signin`; if a future Dify release redirects it server-side, switch to `/install` or remove the healthcheck.
