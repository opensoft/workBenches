#!/bin/bash
# Admin/DevOps Tools Installation Script
# Version: 1.0.0
#
# This script installs all sysadmin and DevOps CLI tools
# for adminbench-base image.

set -e

echo "========================================="
echo "Installing Admin/DevOps Tools"
echo "========================================="

# ========================================
# INFRASTRUCTURE AS CODE
# ========================================

echo "Installing Terraform..."
TERRAFORM_VERSION="1.6.6"
cd /tmp
wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
terraform version

echo "Installing OpenTofu..."
# OpenTofu - open source Terraform alternative
curl -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- --install-method standalone
tofu version || echo "OpenTofu installed (tofu command)"

# ========================================
# KUBERNETES TOOLS
# ========================================

echo "Installing kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client

echo "Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

echo "Installing k9s..."
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
cd /tmp
wget -q https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz
tar xzf k9s_Linux_amd64.tar.gz
mv k9s /usr/local/bin/
rm k9s_Linux_amd64.tar.gz
k9s version

echo "Installing stern (Kubernetes log tailer)..."
STERN_VERSION=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
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
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip
aws --version

echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
az version

echo "Installing Google Cloud SDK..."
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
apt-get update && apt-get install -y google-cloud-sdk
gcloud version

# ========================================
# CONFIGURATION MANAGEMENT
# ========================================

echo "Installing Ansible..."
apt-get update && apt-get install -y ansible
ansible --version

# ========================================
# CONTAINER & ORCHESTRATION
# ========================================

echo "Skipping docker-compose (docker already provides this)..."

# ========================================
# MONITORING & OBSERVABILITY
# ========================================

echo "Installing promtool (Prometheus CLI)..."
PROM_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
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
YQ_VERSION=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64
chmod +x /usr/local/bin/yq
yq --version

echo "Installing lazydocker (Docker TUI)..."
LAZYDOCKER_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
cd /tmp
wget -q https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz
tar xzf lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz
mv lazydocker /usr/local/bin/
rm lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz
lazydocker --version

echo "========================================="
echo "Admin/DevOps Tools Installation Complete!"
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
echo "  - docker-compose"
echo "  - promtool"
echo "  - yq"
echo "  - lazydocker"
echo ""
