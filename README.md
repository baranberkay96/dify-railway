# Deploy and Host Dify with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/dify-v1-ai-app-studio)

Dify is an open-source platform for building LLM applications: chatbots, RAG knowledge bases, agents and multi-step workflows, designed in a visual editor and published as web apps or APIs. This community template runs the complete Dify 1.17 stack on Railway behind a single HTTPS URL.

## About Hosting Dify

Self-hosting Dify means running far more than one container. The console (Next.js) talks to a Flask API; Celery workers index documents and execute workflows; a beat scheduler fires timed jobs; a plugin daemon installs and runs model/tool plugins; a code sandbox executes user code; and the new Agent backend drives sandboxed agent shells. Postgres stores metadata, Redis carries queues and locks, Weaviate holds embeddings, and uploaded files need object storage. This template wires all of it with generated secrets, private networking, a Railway Bucket for files, persistent volumes for stateful services, and an nginx gateway that reproduces Dify's own routing on one domain.

## Common Use Cases

- Internal knowledge assistants that answer from your PDFs, wikis and policies (RAG with citations)
- Customer-facing chatbots and embeddable chat widgets backed by any LLM provider
- Multi-step AI workflows (classification, extraction, summarisation) exposed as an API for your products
- Tool-using agents that browse, call APIs and run code in a sandbox
- A shared, governed LLM workspace where teams build and publish AI apps without writing backend code

## Dependencies for Dify Hosting

- Dify API, Worker, Worker Beat and WebSocket (`langgenius/dify-api`), Web (`langgenius/dify-web`)
- Dify Plugin Daemon, Code Sandbox, Agent Backend and Agent Sandbox
- PostgreSQL (metadata), Redis (queues, cache, locks), Weaviate (vector store)
- Railway Bucket (S3-compatible file storage)
- nginx gateway and two Squid SSRF proxies (built from this repository)

### Deployment Dependencies

- Dify source and self-hosting guide: https://github.com/langgenius/dify and https://docs.dify.ai/en/self-host/quick-start/docker-compose
- Dify environment variables: https://docs.dify.ai/en/self-host/configuration/environments
- Dify Plugin Daemon: https://github.com/langgenius/dify-plugin-daemon
- Dify Sandbox: https://github.com/langgenius/dify-sandbox
- Weaviate configuration: https://docs.weaviate.io/deploy/configuration/env-vars
- Railway Buckets: https://docs.railway.com/guides/storage-buckets

### Implementation Details

| Service | Image | Role | Public |
|---|---|---|---|
| Gateway | nginx 1.30 (repo build) | Single origin; routes `/console/api`, `/api`, `/v1`, `/files`, `/mcp`, `/triggers` → API, `/socket.io/` → WebSocket, `/e/` → Plugin Daemon, `/` → Web | **yes** |
| Web | `dify-web:1.17.1` | Console and published web apps | no |
| API | `dify-api:1.17.1` | REST API, runs DB migrations | no |
| API WebSocket | `dify-api:1.17.1` | Real-time collaborative editing | no |
| Worker | `dify-api:1.17.1` | Celery: indexing, workflows, mail, plugins | no |
| Worker Beat | `dify-api:1.17.1` | Celery beat: scheduled tasks and triggers | no |
| Plugin Daemon | `dify-plugin-daemon:0.6.10-local` | Installs and runs plugins (volume) | no |
| Sandbox | `dify-sandbox:0.2.15` | Executes Code nodes (volume for extra packages) | no |
| SSRF Proxy | Squid (repo build) | Egress filter blocking private networks | no |
| Agent Backend | `dify-agent-backend:1.17.1` | Agent run orchestration | no |
| Agent Sandbox | `dify-agent-local-sandbox:1.17.1` (repo build) | Agent shell workspaces and home snapshots (volume) | no |
| Agent SSRF Proxy | Squid (repo build) | Egress filter for the agent sandbox | no |
| Weaviate | `weaviate:1.39.11` | Vector store (volume) | no |
| Postgres / Redis | Railway base images | Metadata / queues and cache | no |
| Bucket | Railway Bucket | Uploaded files and generated assets | — |

**First login**

1. Wait until API logs show the migrations finished (1–3 minutes on first boot).
2. Open the Gateway URL and go to `/install`. Dify asks for the init password: copy `INIT_PASSWORD` from the **API** service variables.
3. Create the owner account, then add a model provider under *Settings → Model Provider* (installs a plugin from the Dify marketplace).

**Custom domain:** add it to the **Gateway** service, then set `DIFY_PUBLIC_URL` on **API** to `https://your.domain` and `NEXT_PUBLIC_SOCKET_URL` on **Web** to `wss://your.domain`, and redeploy.

**Email (optional):** set `MAIL_TYPE` (`smtp` or `resend`), `MAIL_DEFAULT_SEND_FROM` and the SMTP or Resend variables on API, Worker and Worker Beat to enable invitations and password resets.

**Scaling workers:** increase replicas on **Worker** (stateless) or raise `CELERY_WORKER_AMOUNT`. Keep **Worker Beat** at one replica. For more API throughput raise `SERVER_WORKER_AMOUNT` on API. Keep total database connections below Postgres' limit of 100.

**Pinning and upgrading:** every image is pinned. To upgrade, read the Dify release notes, then change all `1.17.1` tags together (API, API WebSocket, Worker, Worker Beat, Web, Agent Backend and the Agent Sandbox Dockerfile) and update Plugin Daemon, Sandbox and Weaviate to the tags in that release's `docker/docker-compose.yaml`. The API service applies database migrations on start. Back up Postgres (and the Weaviate volume) before major upgrades.

**License note:** Dify is distributed under the Dify Open Source License (Apache 2.0 with additional conditions). Running it for your own organisation is permitted; operating it as a multi-tenant service for third parties, or removing Dify's logo/copyright from the console, requires a commercial license from LangGenius. This is a community template and is not affiliated with LangGenius.

### Why Deploy Dify on Railway?

Railway runs all fifteen Dify services in one project with private networking, managed TLS, persistent volumes and an S3-compatible bucket, so you get a production-shaped Dify without maintaining servers or Docker Compose. Scale workers with a slider, roll back a deploy in one click, and pay for the resources the stack actually uses.
