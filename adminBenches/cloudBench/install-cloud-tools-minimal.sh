#!/bin/bash
# Layer 2 Cloud Admin Tools Installation Script (Minimal)
# Core action-oriented cloud tools only

set -e

echo "=========================================="
echo "Installing Layer 2 Cloud Admin Tools"
echo "=========================================="

# ========================================
# INFRASTRUCTURE AS CODE
# ========================================

echo "Installing Terragrunt..."
curl -L "https://github.com/gruntwork-io/terragrunt/releases/download/v0.71.3/terragrunt_linux_amd64" -o /usr/local/bin/terragrunt
chmod +x /usr/local/bin/terragrunt
terragrunt --version

echo "Installing Pulumi..."
curl -fsSL https://get.pulumi.com | sh
mv /root/.pulumi/bin/* /usr/local/bin/
pulumi version

# ========================================
# COST & FINOPS
# ========================================

echo "Installing Infracost..."
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
mv /usr/local/bin/infracost-linux-amd64 /usr/local/bin/infracost 2>/dev/null || true
infracost --version

# ========================================
# SECURITY & COMPLIANCE
# ========================================

# Prowler and Checkov skipped - large Python dependencies
# Install manually if needed: pip install prowler checkov

echo "Installing Trivy..."
curl -L "https://github.com/aquasecurity/trivy/releases/download/v0.58.2/trivy_0.58.2_Linux-64bit.tar.gz" -o /tmp/trivy.tar.gz
tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy
rm /tmp/trivy.tar.gz
chmod +x /usr/local/bin/trivy
trivy --version

echo "Installing Vault CLI..."
curl -L "https://releases.hashicorp.com/vault/1.19.2/vault_1.19.2_linux_amd64.zip" -o /tmp/vault.zip
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

echo "Installing Velero..."
curl -L "https://github.com/vmware-tanzu/velero/releases/download/v1.16.0/velero-v1.16.0-linux-amd64.tar.gz" -o /tmp/velero.tar.gz
tar -xzf /tmp/velero.tar.gz -C /tmp
mv /tmp/velero-v1.16.0-linux-amd64/velero /usr/local/bin/
rm -rf /tmp/velero*
chmod +x /usr/local/bin/velero
velero version --client-only

# ========================================
# OBSERVABILITY MANAGEMENT
# ========================================

echo "Installing Teleport..."
curl -L "https://cdn.teleport.dev/teleport-v18.2.0-linux-amd64-bin.tar.gz" -o /tmp/teleport.tar.gz
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
echo ""
echo "Core Tools Installed:"
echo "  - Terragrunt, Pulumi (IaC)"
echo "  - Infracost (Cost)"
echo "  - Trivy, Vault (Security)"
echo "  - Helm, Velero (Cluster)"
echo "  - Teleport (Access)"
echo ""
echo "Skipped (install manually if needed):"
echo "  - Prowler, Checkov (large Python deps)"
echo "  - CloudQuery, SkyPilot, Steampipe, Komiser, Grafana CLI"
