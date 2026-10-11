# Dify Agent local sandbox (shellctl) adapted for Railway:
#  - Railway mounts volumes owned by root, so the container starts as root, hands the
#    /home/dify volume (agent homes + home snapshots) to the unprivileged "dify" user,
#    then drops privileges before starting shellctl.
#  - shellctl listens on [::] so it is reachable on IPv6-only private networks.
FROM langgenius/dify-agent-local-sandbox:1.17.1

USER root
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh

EXPOSE 5004
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/railway-entrypoint.sh"]
