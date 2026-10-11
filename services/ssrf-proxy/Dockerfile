# Squid forward proxy used by Dify as its SSRF guard.
# One image, two Railway services:
#   SSRF_PROXY_MODE=default -> "SSRF Proxy"       (API, workers, plugins and code sandbox egress)
#   SSRF_PROXY_MODE=agent   -> "Agent SSRF Proxy" (egress of the Dify Agent sandbox)
# Policy re-created from Dify v1.17.1 docker/ssrf_proxy/*.template for Railway's private network.
FROM ubuntu/squid:6.6-24.04_beta

COPY squid-common.conf.template /etc/squid/templates/dify_common.conf.template
COPY squid-default.conf.template /etc/squid/templates/squid-default.conf.template
COPY squid-agent.conf.template /etc/squid/templates/squid-agent.conf.template
COPY entrypoint.sh /usr/local/bin/dify-ssrf-entrypoint.sh
RUN chmod 0755 /usr/local/bin/dify-ssrf-entrypoint.sh

ENV SSRF_PROXY_MODE=default \
    HTTP_PORT=3128 \
    COREDUMP_DIR=/var/spool/squid

EXPOSE 3128
ENTRYPOINT ["/usr/local/bin/dify-ssrf-entrypoint.sh"]
