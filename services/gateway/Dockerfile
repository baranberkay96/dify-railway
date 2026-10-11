# Dify gateway for Railway: one public origin in front of Web, API, API WebSocket and Plugin Daemon.
# Mirrors the routing of Dify's own nginx (docker/nginx/conf.d/default.conf.template, v1.17.1),
# but resolves Railway private hostnames at request time so services can start in any order.
FROM nginx:1.30.5-alpine

# 15-local-resolvers.envsh exports NGINX_LOCAL_RESOLVERS from /etc/resolv.conf (IPv6-aware).
# The envsubst filter keeps nginx runtime variables ($host, $http_upgrade, ...) untouched.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    NGINX_ENVSUBST_FILTER="^(PORT|DIFY_|NGINX_)" \
    PORT=8080 \
    NGINX_CLIENT_MAX_BODY_SIZE=100M \
    NGINX_PROXY_TIMEOUT=3600s

RUN rm -f /etc/nginx/conf.d/default.conf
COPY snippets/ /etc/nginx/snippets/
COPY templates/ /etc/nginx/templates/

EXPOSE 8080
