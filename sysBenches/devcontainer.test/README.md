# Layer 1b Admin Bench Test Environment

Test harness for the `adminbench-base:brett` image. This validates all admin/DevOps tools are properly installed.

## Tools Tested

### Infrastructure as Code
- Terraform
- OpenTofu
- Ansible

### Kubernetes
- kubectl
- Helm
- k9s
- stern

### Cloud Providers
- AWS CLI
- Azure CLI
- gcloud CLI

### Monitoring & Utilities
- promtool
- yq
- lazydocker
- jq

## Usage

### Quick Test
```bash
docker compose up -d
docker compose exec test /test/test.sh
docker compose down
```

### Interactive Session
```bash
docker compose up -d
docker compose exec test zsh
# Test tools manually
docker compose down
```

### Open in VSCode
Open this directory in VSCode and reopen in the container. The test.sh script will be available at `/test/test.sh`.

## Requirements

The `adminbench-base:brett` image must be built first:
```bash
cd ../base-image
./build.sh --user brett
```
