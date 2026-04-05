# CloudBench - Layer 2 Cloud Administration

Cloud administration bench with action-oriented tools for infrastructure changes.

## Quick Start

### Build the Image
```bash
./build-layer2.sh --user brett
```

### Create a Workspace
```bash
cp -r devcontainer.example workspaces/my-project
cd workspaces/my-project
code .  # Open in VSCode and reopen in container
```

## What's Included

### Layer 2 Tools (Action & Change)
- **IaC**: Terragrunt, Pulumi
- **Cost**: Infracost
- **Security**: Trivy, Vault CLI
- **Cluster**: Helm, Velero
- **Access**: Teleport (tsh, tctl)

### Inherited from Layer 1b (Read-Only)
- Terraform, OpenTofu, kubectl, k9s, stern
- AWS CLI, Azure CLI, gcloud
- Ansible

### Inherited from Layer 0 (System)
- zsh with Oh-My-Zsh, tmux, fzf, bat, zoxide
- neovim, jq, yq, tldr

## Architecture Philosophy

**Layer 1b = "Discovery & Connection"**
- Read-only troubleshooting
- The container you spin up at 2 AM
- No write permissions needed

**Layer 2 = "Action & Change"**
- Infrastructure modifications
- Stateful operations
- Requires write permissions

## Testing

```bash
cd devcontainer.test
docker compose up -d
docker compose exec test /test/test.sh
docker compose down
```

Expected: 18/18 tests passing

## Documentation

See [.warp/warp.md](.warp/warp.md) for complete architecture documentation.

## Security Model

- Cloud credentials mounted read-only from host
- Write permissions controlled at workspace level
- Clear separation between inspection (Layer 1b) and modification (Layer 2)

## Workspace Template

The `devcontainer.example` includes:
- VSCode devcontainer configuration
- Docker compose with cloud credential mounts
- Recommended VSCode extensions for cloud work

## Version

- Layer: 2
- Type: cloud-admin
- Version: 1.0.0
- Base: adminbench-base (Layer 1b)
