FROM docker:28-cli AS docker-cli
FROM node:24-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3 jq zsh sudo openssl ca-certificates curl procps \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global npm@12.0.2 \
    && printf 'node ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/acceptance-node
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
RUN printf '#!/bin/sh\nexec docker compose "$@"\n' > /usr/local/bin/docker-compose \
    && chmod 755 /usr/local/bin/docker-compose
ENV USER=node HOME=/home/node SHELL=/bin/bash DOCKER_HOST=unix:///var/run/docker.sock
WORKDIR /home/node
