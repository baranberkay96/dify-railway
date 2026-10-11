# Notice

## Upstream software

| Software | License | Images used (publisher) |
|---|---|---|
| Dify (API, Web, Agent Backend, Agent Local Sandbox) | Dify Open Source License — Apache License 2.0 with additional conditions (no multi-tenant service without authorisation; do not remove the console LOGO/copyright). © 2025 LangGenius, Inc. | `langgenius/dify-api:1.17.1`, `langgenius/dify-web:1.17.1`, `langgenius/dify-agent-backend:1.17.1`, `langgenius/dify-agent-local-sandbox:1.17.1` (LangGenius) |
| Dify Plugin Daemon | Apache-2.0 | `langgenius/dify-plugin-daemon:0.6.10-local` (LangGenius) |
| Dify Sandbox | Apache-2.0 | `langgenius/dify-sandbox:0.2.15` (LangGenius) |
| Weaviate | BSD-3-Clause | `semitechnologies/weaviate:1.39.11` (Weaviate B.V.) |
| nginx | BSD-2-Clause | `nginx:1.30.5-alpine` (Docker Official Image) |
| Squid | GPL-2.0-or-later | `ubuntu/squid:6.6-24.04_beta` (Canonical) |
| PostgreSQL | PostgreSQL License | `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway) |
| Redis | RSALv2 / SSPLv1 / AGPLv3 (Redis 8 tri-license) | `redis:8.2` (Docker Official Image) |

## Verified against

| What | Upstream file | Ref | URL | Checked |
|---|---|---|---|---|
| Service list, images, env per service | `docker/docker-compose-template.yaml`, `docker/docker-compose.yaml` | `1.17.1` | https://github.com/langgenius/dify/tree/1.17.1/docker | 2026-10-10 |
| Default variables | `docker/.env.example`, `docker/envs/core-services/*.env.example`, `docker/envs/security.env.example`, `docker/envs/infrastructure/ssrf-proxy.env.example`, `docker/envs/vectorstores/weaviate.env.example` | `1.17.1` | same | 2026-10-10 |
| Gateway routes | `docker/nginx/conf.d/default.conf.template`, `docker/nginx/proxy.conf.template` | `1.17.1` | same | 2026-10-10 |
| SSRF policy | `docker/ssrf_proxy/squid.conf.template`, `squid-agent.conf.template`, `squid-common.conf.template`, `docker-entrypoint.sh`, `docker-agent-entrypoint.sh` | `1.17.1` | same | 2026-10-10 |
| API modes, bind address, migrations | `api/docker/entrypoint.sh` | `1.17.1` | https://github.com/langgenius/dify/blob/1.17.1/api/docker/entrypoint.sh | 2026-10-10 |
| Web runtime variables | `web/docker/entrypoint.sh`, `web/proxy.ts` | `1.17.1` | https://github.com/langgenius/dify/tree/1.17.1/web | 2026-10-10 |
| S3 options | `api/configs/middleware/storage/amazon_s3_storage_config.py` | `1.17.1` | https://github.com/langgenius/dify/tree/1.17.1/api/configs | 2026-10-10 |
| Agent backend settings, secret format | `dify-agent/Dockerfile`, `dify-agent/src/dify_agent/server/settings.py`, `.../agent_stub/server/tokens/agent_stub.py`, `.../runtime_backend/local.py` | `1.17.1` | https://github.com/langgenius/dify/tree/1.17.1/dify-agent | 2026-10-10 |
| Agent sandbox user, listen flag, Landlock | `dify-agent-runtime/docker/Dockerfile`, `internal/server/config.go`, `cmd/shellctl/main.go`, `internal/landlock/landlock_linux.go` | `1.17.1` | https://github.com/langgenius/dify/tree/1.17.1/dify-agent-runtime | 2026-10-10 |
| Plugin daemon config, DB auto-create, bind address | `.env.example`, `internal/types/app/config.go`, `internal/types/app/default.go`, `internal/db/pg/pg.go`, `internal/server/http_server.go` | `0.6.10` | https://github.com/langgenius/dify-plugin-daemon/tree/0.6.10 | 2026-10-10 |
| Sandbox bind address | `internal/server/server.go` | `0.2.15` | https://github.com/langgenius/dify-sandbox/tree/0.2.15 | 2026-10-10 |
| Weaviate entrypoint / flags | `Dockerfile` | `v1.39.2` | https://github.com/weaviate/weaviate/blob/v1.39.2/Dockerfile | 2026-10-10 |
| nginx resolver / envsubst behaviour | `entrypoint/15-local-resolvers.envsh`, `entrypoint/20-envsubst-on-templates.sh` | `master` | https://github.com/nginx/docker-nginx/tree/master/entrypoint | 2026-10-10 |
| Railway Buckets | Storage Buckets guide | — | https://docs.railway.com/guides/storage-buckets | 2026-10-10 |

## Adapted code

| Our file | Source | Copyright / license | Changes |
|---|---|---|---|
| `services/gateway/templates/dify.conf.template`, `services/gateway/snippets/dify_proxy.conf` | `langgenius/dify` `docker/nginx/conf.d/default.conf.template`, `docker/nginx/proxy.conf.template` (1.17.1) | © 2025 LangGenius, Inc. — Dify Open Source License (Apache-2.0 based) | Same route table; upstream hostnames replaced by Railway private-domain variables; resolver taken from `/etc/resolv.conf` (IPv6-aware); IPv4+IPv6 listen; Railway `X-Forwarded-Proto` preserved; `/healthz` added; certbot/HTTPS blocks removed |
| `services/ssrf-proxy/squid-common.conf.template`, `squid-default.conf.template`, `squid-agent.conf.template`, `entrypoint.sh` | `langgenius/dify` `docker/ssrf_proxy/*` (1.17.1) | © 2025 LangGenius, Inc. — Dify Open Source License (Apache-2.0 based) | ACL policy kept; agent destinations parameterised with Railway hostnames; one image with `SSRF_PROXY_MODE`; dropped `tcp_outgoing_address 0.0.0.0` and the middleware-only sandbox bridge; cache 256 MB → 32 MB; entrypoint rewritten |
| `services/agent-sandbox/Dockerfile`, `railway-entrypoint.sh` | Written for this template (wraps the published image) | — | — |
| `services/gateway/Dockerfile`, `services/ssrf-proxy/Dockerfile` | Written for this template | — | — |

Variable names/defaults in `template.json` follow Dify's documented configuration keys.

## Reference only (not copied)

- Marketplace templates `TiT2V6` ("Dify v1.17.1"), `V1xiql` ("Dify"), `dify-ai-workflow` ("Dify | Open-Source AI/LLM App Builder"): no license; read for ideas (service split, variable set, gateway idea). No files or text copied; all secrets regenerated.
- No `_upstream` repositories were provided for this app.

## Trademarks

"Dify" and the Dify logo belong to LangGenius, Inc.; "Weaviate" to Weaviate B.V.; "Railway" to Railway Corporation. This is a community template and is not affiliated with or endorsed by these companies.
