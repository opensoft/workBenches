#!/bin/bash
# Layer 2 Cloud Admin Tools Installation Script
# Installs action-oriented cloud tools on top of adminbench-base (Layer 1b)

set -e

echo "=========================================="
echo "Installing Layer 2 Cloud Admin Tools"
echo "=========================================="

# ========================================
# INFRASTRUCTURE AS CODE
# ========================================

echo "Installing Terragrunt..."
TERRAGRUNT_VERSION=$(curl -s https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/' | head -1)
if [ -z "$TERRAGRUNT_VERSION" ]; then
    TERRAGRUNT_VERSION="0.71.3"
fi
curl -L "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64" -o /usr/local/bin/terragrunt
chmod +x /usr/local/bin/terragrunt
terragrunt --version

echo "Installing Pulumi..."
curl -fsSL https://get.pulumi.com | sh
mv /root/.pulumi/bin/* /usr/local/bin/
pulumi version

# ========================================
# CLOUD INTELLIGENCE & SEARCH
# ========================================

echo "Installing Steampipe..."
STEAMPIPE_VERSION=$(curl -s https://api.github.com/repos/turbot/steampipe/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/' | head -1)
if [ -z "$STEAMPIPE_VERSION" ]; then
    STEAMPIPE_VERSION="1.0.0"
fi
curl -L "https://github.com/turbot/steampipe/releases/download/v${STEAMPIPE_VERSION}/steampipe_linux_amd64.tar.gz" -o /tmp/steampipe.tar.gz
tar -xzf /tmp/steampipe.tar.gz -C /usr/local/bin steampipe
rm /tmp/steampipe.tar.gz
chmod +x /usr/local/bin/steampipe
echo "Steampipe v${STEAMPIPE_VERSION} installed (version check requires non-root user)"

# CloudQuery - skipping, complex API structure
echo "CloudQuery skipped (install manually if needed)"

# SkyPilot - skipping, large dependency
echo "SkyPilot skipped (install manually if needed)"

# ========================================
# COST & FINOPS
# ========================================

echo "Installing Infracost..."
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
mv /usr/local/bin/infracost-linux-amd64 /usr/local/bin/infracost 2>/dev/null || true
infracost --version

echo "Installing Komiser..."
KOMISER_VERSION=$(curl -s https://api.github.com/repos/tailwarden/komiser/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/' | head -1)
if [ -z "$KOMISER_VERSION" ]; then
    KOMISER_VERSION="3.11.0"
fi
curl -L "https://github.com/tailwarden/komiser/releases/download/v${KOMISER_VERSION}/komiser_${KOMISER_VERSION}_Linux_x86_64.tar.gz" -o /tmp/komiser.tar.gz
tar -xzf /tmp/komiser.tar.gz -C /tmp
mv /tmp/komiser /usr/local/bin/
rm /tmp/komiser.tar.gz
chmod +x /usr/local/bin/komiser
komiser version

# nOps is SaaS-based, skipping CLI installation

# ========================================
# SECURITY & COMPLIANCE
# ========================================

echo "Installing Prowler..."
pip3 install --break-system-packages prowler
prowler --version

echo "Installing Checkov..."
pip3 install --break-system-packages checkov
checkov --version

echo "Installing Trivy..."
TRIVY_VERSION=$(curl -s https://api.github.com/repos/aquasecurity/trivy/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -L "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" -o /tmp/trivy.tar.gz
tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy
rm /tmp/trivy.tar.gz
chmod +x /usr/local/bin/trivy
trivy --version

echo "Installing Vault CLI..."
VAULT_VERSION=$(curl -s https://api.github.com/repos/hashicorp/vault/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -L "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip
unzip -o /tmp/vault.zip -d /usr/local/bin
rm /tmp/vault.zip
chmod +x /usr/local/bin/vault
vault --version

# ========================================
# CLUSTER MANAGEMENT
# ========================================

echo "Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

echo "Installing Karpenter CLI..."
# Karpenter is managed via kubectl/helm, but we can install kubectl-karpenter plugin
KARPENTER_VERSION=$(curl -s https://api.github.com/repos/aws/karpenter/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/' || echo "0.37.0")
echo "Note: Karpenter managed via kubectl/helm (v${KARPENTER_VERSION})"

echo "Installing Velero..."
VELERO_VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -L "https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-amd64.tar.gz" -o /tmp/velero.tar.gz
tar -xzf /tmp/velero.tar.gz -C /tmp
mv /tmp/velero-v${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
rm -rf /tmp/velero*
chmod +x /usr/local/bin/velero
velero version --client-only

# ========================================
# OBSERVABILITY MANAGEMENT
# ========================================

echo "Installing Grafana CLI..."
GRAFANA_VERSION=$(curl -s https://api.github.com/repos/grafana/grafana/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -L "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz" -o /tmp/grafana.tar.gz
tar -xzf /tmp/grafana.tar.gz -C /tmp
mv /tmp/grafana-v${GRAFANA_VERSION}/bin/grafana-cli /usr/local/bin/
rm -rf /tmp/grafana*
chmod +x /usr/local/bin/grafana-cli
grafana-cli --version

echo "Installing Teleport..."
TELEPORT_VERSION=$(curl -s https://api.github.com/repos/gravitational/teleport/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -L "https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz" -o /tmp/teleport.tar.gz
tar -xzf /tmp/teleport.tar.gz -C /tmp
mv /tmp/teleport/tsh /usr/local/bin/
mv /tmp/teleport/tctl /usr/local/bin/
rm -rf /tmp/teleport*
chmod +x /usr/local/bin/tsh /usr/local/bin/tctl
tsh version

echo ""
echo "=========================================="
echo "✓ Layer 2 Cloud Tools Installation Complete"
echo "=========================================="
