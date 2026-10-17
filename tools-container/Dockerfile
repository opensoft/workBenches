FROM docker:28-cli AS docker-cli

FROM python:3.13-alpine
RUN apk --timeout 20 add --no-cache bash ca-certificates curl git jq openssh-client ncurses-terminfo-base \
    && python3 --version && jq --version && git --version && curl --version
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
COPY --chmod=0644 workbenches_host.py host-command /opt/workbenches/
RUN chmod 0755 /opt/workbenches/host-command \
    && python3 -c 'import shutil, sysconfig; shutil.copy("/opt/workbenches/workbenches_host.py", sysconfig.get_paths()["purelib"])' \
    && mkdir -p /opt/workbenches/host-bin \
    && for name in gh node npm uv wsl.exe powershell.exe pwsh.exe xdg-open open \
       docker-credential-desktop docker-credential-osxkeychain docker-credential-secretservice \
       docker-credential-pass docker-credential-wincred; do \
         ln -s /opt/workbenches/host-command /opt/workbenches/host-bin/"$name"; \
       done
ENV PATH=/opt/workbenches/host-bin:$PATH \
    PYTHONPATH=/opt/workbenches \
    PYTHONDONTWRITEBYTECODE=1
HEALTHCHECK --interval=3s --timeout=5s --start-period=1s --retries=2 \
    CMD python3 -c 'import workbenches_host' && jq --version && git --version && curl --version
CMD ["sleep", "infinity"]
