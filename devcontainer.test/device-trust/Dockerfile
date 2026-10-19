FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server sudo \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1000 --create-home brett && passwd -d brett \
    && useradd --create-home other && passwd -d other \
    && mkdir -p /run/sshd \
    && printf 'brett ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/device-test
USER 1000:1000
ENV PYTHONDONTWRITEBYTECODE=1 WORKBENCHES_DEVICE_SSH_TEST=1 HOME=/home/brett
WORKDIR /source
CMD ["python3", "devcontainer.test/test-device-trust.py"]
