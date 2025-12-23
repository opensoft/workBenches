# CloudBench Layer 2 Architecture

## Overview
CloudBench is a Layer 2 specialized bench for cloud administration tasks. It extends the adminbench-base (Layer 1b) with action-oriented tools focused on modifying infrastructure state.

## Layer Philosophy

### Layer 0: System Foundation
- Location: `workBenches/base-image/`
- Purpose: System tools and modern CLI utilities
- Tools: zsh, Oh-My-Zsh, tmux, fzf, bat, zoxide, tldr, neovim, jq, yq
- User: Configured with host user (brett)

### Layer 1b: Admin Visibility ("Discovery & Connection")
- Location: `adminBenches/base-image/`
- Purpose: Read-only troubleshooting and inspection
- Philosophy: "The container you spin up at 2 AM"
- Tools: Terraform (show/plan), kubectl (get/describe), stern (logs), k9s (monitoring), cloud CLIs (verification), Ansible (ad-hoc)
- Security: Does NOT need write permissions to cloud resources

### Layer 2: Cloud Admin ("Action & Change")
- Location: `adminBenches/cloudBench/`
- Purpose: Infrastructure modifications and stateful operations
- Philosophy: "Tools that change infrastructure state"
- Tools: IaC execution, cost optimization, security scanning, cluster management
- Security: Requires write permissions - only enabled in Layer 2 workspaces

## Tool Categories

### Infrastructure as Code - Full Logic
- **Terragrunt** - DRY wrapper for multi-environment Terraform
- **Pulumi** - Alternative to Terraform using Python/Go
- Ansible Playbooks - Complex versioned playbooks (binary in Layer 1b)

### Cost & FinOps
- **Infracost** - Terraform cost estimation BEFORE apply

### Security & Compliance (Pre-deployment)
- **Trivy** - CVE scanning for infrastructure
- **Vault CLI** - Secrets management (HashiCorp)

### Cluster Management (Write Operations)
- **Helm** - Application packaging and deployment
- **Velero** - K8s cluster backup and migration

### Observability & Access
- **Teleport (tsh/tctl)** - Unified access plane provisioning

### Tools Skipped (Install Manually if Needed)
- Prowler, Checkov (large Python dependencies)
- CloudQuery, SkyPilot, Steampipe, Komiser, Grafana CLI

## Workspace Creation Workflow

### 1. Build Layer 2 Image (One Time)
```bash
cd /home/brett/projects/workBenches/adminBenches/cloudBench
./build-layer2.sh --user brett
```

### 2. Create New Workspace
```bash
cp -r devcontainer.example workspaces/my-cloud-project
cd workspaces/my-cloud-project
# Edit docker-compose.yml if needed
code .
# Reopen in container
```

### 3. Workspace Startup Time
- Layer 0 + 1b + 2 already built
- Workspace instantiation: < 10 seconds
- No tool installation during workspace creation

## Layer Benefits

### Security Model
- **Layer 1b**: Read-only access for troubleshooting
  - Can inspect: `terraform show`, `kubectl get`, cloud resource listings
  - Cannot modify: No `terraform apply`, no cluster writes

- **Layer 2**: Write access only where needed
  - Workspaces explicitly grant cloud write permissions
  - Clear separation between inspection and modification

### AI Agent Focus
Layer 2 can run AI agents (like Kubiya CLI) with focused system prompts:
- "You are an AWS Architect. Focus on VPCs and IAM."
- "Manage Terraform state for multi-environment deployments."
- "Scan and remediate security issues before deployment."

### Upgrade Path
- Update Layer 2: Rebuild image, all workspaces inherit changes
- No need to update individual workspaces
- Workspace-specific tools installed via workspace Dockerfile if needed

## Example Commands by Tool Category

### Infrastructure as Code
```bash
# Terragrunt multi-environment
terragrunt run-all plan
terragrunt run-all apply

# Pulumi
pulumi up
pulumi stack select production
```

### Cost Optimization
```bash
# Check Terraform cost before apply
infracost breakdown --path .
infracost diff --path . --compare-to main
```

### Security Scanning
```bash
# Scan infrastructure for CVEs
trivy config .

# Manage secrets
vault kv get secret/prod/db-password
```

### Cluster Management
```bash
# Deploy applications
helm install myapp ./chart
helm upgrade myapp ./chart

# Backup cluster
velero backup create my-backup
velero restore create --from-backup my-backup
```

### Access Management
```bash
# Teleport unified access
tsh login --proxy=teleport.example.com
tsh ssh user@host
tsh kube login my-cluster
```

## Architecture Diagram

```
Layer 0 (workbench-base)
    System Foundation
    ↓
Layer 1b (adminbench-base)
    Admin Visibility (Read-Only)
    Tools: kubectl, stern, terraform show, cloud CLIs
    ↓
Layer 2 (cloud-bench)
    Cloud Admin (Action & Change)
    Tools: Terragrunt, Pulumi, Infracost, Security, Helm
    ↓
Workspaces
    Project-specific cloud admin work
    Mounted: ~/.aws, ~/.azure, ~/.kube, ~/.ssh
    Write permissions to cloud resources
```

## Testing

Run the test suite to validate all tools:
```bash
cd devcontainer.test
docker compose up -d
docker compose exec test /test/test.sh
docker compose down
```

Expected: 18 tests passing
- 2 IaC tools
- 1 Cost tool
- 2 Security tools
- 2 Cluster tools
- 2 Access tools
- 5 Layer 1b inherited tools
- 4 Environment checks
