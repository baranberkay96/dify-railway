#!/bin/bash
# Renders the Squid config for the selected mode and starts Squid in the foreground.
set -euo pipefail

MODE="${SSRF_PROXY_MODE:-default}"
case "$MODE" in
  default) TEMPLATE=/etc/squid/templates/squid-default.conf.template ;;
  agent)
    TEMPLATE=/etc/squid/templates/squid-agent.conf.template
    : "${DIFY_AGENT_BACKEND_HOST:?DIFY_AGENT_BACKEND_HOST is required in agent mode}"
    : "${DIFY_API_HOST:?DIFY_API_HOST is required in agent mode}"
    ;;
  *) echo "[ssrf-proxy] unknown SSRF_PROXY_MODE '$MODE' (use default|agent)" >&2; exit 1 ;;
esac

# Optional allow-list for private targets (comma or space separated).
ALLOW_CONF=/etc/squid/dify_allow_private.conf
echo "# generated at container start" > "$ALLOW_CONF"
write_allow() {
  local values="${1//,/ }" acl_name="$2" acl_type="$3"
  [ -z "${values//[[:space:]]/}" ] && return 0
  printf 'acl %s %s %s\nhttp_access allow client_localnet %s\n' "$acl_name" "$acl_type" "$values" "$acl_name" >> "$ALLOW_CONF"
}
write_allow "${SSRF_PROXY_ALLOW_PRIVATE_IPS:-}" dify_allowed_private_networks dst
write_allow "${SSRF_PROXY_ALLOW_PRIVATE_DOMAINS:-}" dify_allowed_private_domains dstdomain

# ${VAR} substitution without touching anything else in the templates.
render() {
  awk '{
    while (match($0, /\$\{[A-Za-z_][A-Za-z_0-9]*\}/)) {
      name = substr($0, RSTART + 2, RLENGTH - 3)
      $0 = substr($0, 1, RSTART - 1) ENVIRON[name] substr($0, RSTART + RLENGTH)
    }
    print
  }' "$1"
}
render /etc/squid/templates/dify_common.conf.template > /etc/squid/dify_common.conf
render "$TEMPLATE" > /etc/squid/squid.conf

# Forward Squid's log files to the container log stream.
mkdir -p /var/log/squid && chown proxy:proxy /var/log/squid 2>/dev/null || true
for f in access cache; do
  touch "/var/log/squid/$f.log"; chown proxy:proxy "/var/log/squid/$f.log" 2>/dev/null || true
  tail -F "/var/log/squid/$f.log" 2>/dev/null &
done

/usr/sbin/squid -f /etc/squid/squid.conf -k parse
/usr/sbin/squid -f /etc/squid/squid.conf -Nz
echo "[ssrf-proxy] starting squid in '$MODE' mode on port ${HTTP_PORT}"
exec /usr/sbin/squid -f /etc/squid/squid.conf -NYC
