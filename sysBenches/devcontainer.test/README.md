# Layer 1b Sys Bench Test Environment

Test harness for the `sys-bench-base:$USER` image. This validates the Layer 1b tools inside a real user shell environment.

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
- Docker CLI / host daemon access
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

The `sys-bench-base:$USER` image must be built first:
```bash
cd ../base-image
./build.sh
bash ../../scripts/ensure-layer3.sh --base sys-bench-base:latest
```
