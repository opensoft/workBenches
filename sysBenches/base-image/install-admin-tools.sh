#!/bin/bash
# Sys/DevOps Tools Installation Script
# Version: 1.0.2
#
# This script installs all sysadmin and DevOps CLI tools
# for sys-bench-base image.

set -e

CURL_RETRY=(--retry 5 --retry-all-errors --connect-timeout 20)

echo "========================================="
echo "Installing Sys/DevOps Tools"
echo "========================================="

# ========================================
# INFRASTRUCTURE AS CODE
# ========================================

echo "Installing Terraform..."
TERRAFORM_VERSION="1.15.8"
cd /tmp
wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
terraform version

echo "Installing OpenTofu..."
# OpenTofu - open source Terraform alternative
OPENTOFU_VERSION="1.12.3"
curl "${CURL_RETRY[@]}" -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- \
    --install-method standalone \
    --opentofu-version "${OPENTOFU_VERSION}"
tofu version || echo "OpenTofu installed (tofu command)"

# ========================================
# KUBERNETES TOOLS
# ========================================

echo "Installing kubectl..."
KUBECTL_VERSION=$(curl "${CURL_RETRY[@]}" -L -s https://dl.k8s.io/release/stable.txt)
curl "${CURL_RETRY[@]}" -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client

echo "Installing Helm..."
HELM_TAG=$(curl "${CURL_RETRY[@]}" -fsSL https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name"' | sed -E 's/.*"(v[^"]+)".*/\1/' | head -1)
cd /tmp
curl "${CURL_RETRY[@]}" -fsSL "https://get.helm.sh/helm-${HELM_TAG}-linux-amd64.tar.gz" -o "helm-${HELM_TAG}-linux-amd64.tar.gz"
tar xzf "helm-${HELM_TAG}-linux-amd64.tar.gz"
install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 "helm-${HELM_TAG}-linux-amd64.tar.gz"
helm version

echo "Installing k9s..."
K9S_VERSION=$(curl "${CURL_RETRY[@]}" -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
cd /tmp
wget -q https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz
tar xzf k9s_Linux_amd64.tar.gz
mv k9s /usr/local/bin/
rm k9s_Linux_amd64.tar.gz
k9s version

echo "Installing stern (Kubernetes log tailer)..."
STERN_VERSION=$(curl "${CURL_RETRY[@]}" -s https://api.github.com/repos/stern/stern/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
cd /tmp
wget -q https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_amd64.tar.gz
tar xzf stern_${STERN_VERSION}_linux_amd64.tar.gz
mv stern /usr/local/bin/
rm stern_${STERN_VERSION}_linux_amd64.tar.gz
stern --version

# ========================================
# CLOUD PROVIDER CLIs
# ========================================

echo "Installing AWS CLI v2..."
cd /tmp
curl "${CURL_RETRY[@]}" -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip
aws --version

echo "Installing Azure CLI..."
curl "${CURL_RETRY[@]}" -sL https://aka.ms/InstallAzureCLIDeb | bash
az version

echo "Installing Google Cloud SDK..."
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl "${CURL_RETRY[@]}" https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
apt-get update && apt-get install -y google-cloud-sdk
gcloud version

# ========================================
# CONFIGURATION MANAGEMENT
# ========================================

echo "Installing Ansible..."
apt-get update && apt-get install -y python3-pip
python3 -m pip install --break-system-packages --upgrade ansible
ansible --version

# ========================================
# MONITORING & OBSERVABILITY
# ========================================

echo "Installing promtool (Prometheus CLI)..."
PROM_VERSION=$(curl "${CURL_RETRY[@]}" -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
mv prometheus-${PROM_VERSION}.linux-amd64/promtool /usr/local/bin/
rm -rf prometheus-${PROM_VERSION}.linux-amd64*
promtool --version

# ========================================
# UTILITIES
# ========================================

echo "Installing yq (YAML processor)..."
YQ_VERSION=$(curl "${CURL_RETRY[@]}" -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64
chmod +x /usr/local/bin/yq
yq --version

echo "Installing lazydocker (Docker TUI)..."
LAZYDOCKER_VERSION=$(curl "${CURL_RETRY[@]}" -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
cd /tmp
wget -q https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz
tar xzf lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz
mv lazydocker /usr/local/bin/
rm lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz
lazydocker --version

echo "========================================="
echo "Sys/DevOps Tools Installation Complete!"
echo "========================================="
echo ""
echo "Installed tools:"
echo "  - Terraform $(terraform version | head -1)"
echo "  - kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "  - Helm $(helm version --short)"
echo "  - k9s"
echo "  - stern"
echo "  - AWS CLI $(aws --version)"
echo "  - Azure CLI"
echo "  - Google Cloud SDK"
echo "  - Ansible $(ansible --version | head -1)"
echo "  - promtool"
echo "  - yq"
echo "  - lazydocker"
echo ""
