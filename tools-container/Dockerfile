FROM docker:28-cli AS docker-cli
FROM rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS rclone

FROM python:3.13-alpine
RUN apk --timeout 20 add --no-cache bash ca-certificates curl git jq openssh-client ncurses-terminfo-base \
    && python3 --version && jq --version && git --version && curl --version
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY workbenches_host.py host-command rclone_login.py rclone-open /opt/workbenches/
RUN chmod 0755 /opt/workbenches /opt/workbenches/host-command \
    && chmod 0644 /opt/workbenches/workbenches_host.py /opt/workbenches/rclone_login.py \
    && python3 -c 'import shutil, sysconfig; shutil.copy("/opt/workbenches/workbenches_host.py", sysconfig.get_paths()["purelib"])' \
    && chmod 0755 /opt/workbenches/rclone-open \
    && mkdir -p /opt/workbenches/host-bin /opt/workbenches/rclone-browser-bin \
    && ln -s /opt/workbenches/rclone-open /opt/workbenches/rclone-browser-bin/xdg-open \
    && rclone version \
    && for name in gh node npm uv wsl.exe powershell.exe pwsh.exe xdg-open open \
       docker-credential-desktop docker-credential-osxkeychain docker-credential-secretservice \
       docker-credential-pass docker-credential-wincred; do \
         ln -s /opt/workbenches/host-command /opt/workbenches/host-bin/"$name"; \
       done
ENV PATH=/opt/workbenches/host-bin:$PATH \
    PYTHONPATH=/opt/workbenches \
    PYTHONDONTWRITEBYTECODE=1
HEALTHCHECK --interval=3s --timeout=5s --start-period=1s --retries=2 \
    CMD test -r /opt/workbenches/host-command && test -x /opt/workbenches/host-command \
        && python3 -c 'import workbenches_host' && jq --version && git --version && curl --version && rclone version
CMD ["sleep", "infinity"]
