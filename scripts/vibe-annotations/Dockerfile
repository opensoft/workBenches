FROM node:22-bookworm-slim

ARG VIBE_ANNOTATIONS_VERSION=0.5.1

RUN npm install --global "vibe-annotations-server@${VIBE_ANNOTATIONS_VERSION}" \
    && npm cache clean --force

LABEL org.opencontainers.image.title="workBenches Vibe Annotations MCP" \
      org.opencontainers.image.source="https://github.com/RaphaelRegnier/vibe-annotations" \
      org.opencontainers.image.version="${VIBE_ANNOTATIONS_VERSION}"

EXPOSE 3846

ENTRYPOINT ["vibe-annotations-server"]
CMD ["start"]
