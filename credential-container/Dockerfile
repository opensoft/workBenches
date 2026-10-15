# Only public tools enter these layers. Runtime credentials are entered on a TTY.
FROM 1password/op:2.40.0 AS op-cli

FROM python:3.13-alpine AS core
COPY credential_recovery.py /opt/workbenches/credential_recovery.py
ENTRYPOINT ["python3", "/opt/workbenches/credential_recovery.py", "--container"]

FROM core AS onepassword
COPY --from=op-cli /usr/local/bin/op /usr/local/bin/op
RUN op --version

FROM node:22-bookworm-slim AS bitwarden-tools
RUN apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global @bitwarden/cli@2026.9.1 \
    && npm cache clean --force \
    && bw --version && rm -rf /root/.config
FROM bitwarden-tools AS bitwarden
COPY credential_recovery.py /opt/workbenches/credential_recovery.py
ENTRYPOINT ["python3", "/opt/workbenches/credential_recovery.py", "--container"]

FROM bitwarden-tools AS vault
COPY --from=op-cli /usr/local/bin/op /usr/local/bin/op
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/azure \
    && /opt/azure/bin/pip install --no-cache-dir azure-cli==2.91.0 \
    && ln -s /opt/azure/bin/az /usr/local/bin/az \
    && rm -rf /root/.config \
    && az version --query '"azure-cli"' -o tsv && op --version && bw --version
COPY credential_recovery.py /opt/workbenches/credential_recovery.py
ENV HOME=/tmp/vault-home XDG_CONFIG_HOME=/tmp/vault-home/config \
    AZURE_CORE_COLLECT_TELEMETRY=false AZURE_CORE_LOGIN_EXPERIENCE_V2=off
HEALTHCHECK --interval=5s --timeout=8s --start-period=1s --retries=2 \
    CMD python3 --version && op --version && bw --version && az version --query '"azure-cli"' -o tsv
ENTRYPOINT []
CMD ["sleep", "infinity"]
