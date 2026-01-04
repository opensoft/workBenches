# goBench Warp Instructions

## Overview
goBench is a comprehensive Go development container that provides all the tools needed for professional Go development. It follows the same pattern as dotNetBench and javaBench with perfect UID/GID matching for WSL environments.

## Key Features
- **Go 1.22+** with all essential development tools
- **25+ Go tools** pre-installed (gopls, delve, golangci-lint, etc.)
- **Docker & Kubernetes** for cloud-native development
- **Perfect user permissions** matching host system
- **Modern CLI tools** (exa, bat, ripgrep, fzf, zoxide, starship)
- **VSCode optimized** with Go extension and settings

## File Organization
Per user preferences:
- All Warp instructions are in `.warp/` folder off the root
- Dockerfile and docker-compose files are in `.devcontainer/` folder
- Environment example file is in `.devcontainer/.env.example`

## Building the Container

### First Time Setup
```bash
cd /home/brett/projects/workBenches/devBenches/goBench/.devcontainer
export UID=$(id -u) GID=$(id -g) USER=$(whoami)
docker-compose up -d --build
```

### VS Code (Recommended)
1. Open goBench folder in VS Code
2. Click "Reopen in Container" when prompted
3. Wait for build (10-15 minutes first time)

## Container Details

### Ports
The following ports are forwarded to avoid conflicts with other benches:
- `8082:8080` - Primary Go app port
- `8083:8081` - Secondary app port
- `9092:9090` - Metrics/monitoring port
- `3002:3000` - Frontend dev server

### Shared Network
goBench connects to the `dev_bench` network shared by all DevBench containers (dotNetBench, javaBench, etc.).

### Volumes
- `../:/workspace:cached` - Project workspace
- `/var/run/docker.sock` - Docker socket for Docker-in-Docker
- `~/.gitconfig` - Git configuration (read-only)
- `~/.ssh` - SSH keys (read-only)

## Go Tools Installed

### Language Server & Debugging
- `gopls` - Official Go language server
- `dlv` - Delve debugger

### Linting & Analysis
- `golangci-lint` - Meta-linter
- `staticcheck` - Advanced static analysis
- `errcheck` - Check for unchecked errors
- `golint` - Basic linter

### Code Generation & Manipulation
- `goimports` - Auto import management
- `gomodifytags` - Struct tag editor
- `gotests` - Test generator
- `impl` - Interface implementation generator

### Development Tools
- `air` - Live reload for Go apps
- `swag` - Swagger documentation generator
- `wire` - Dependency injection
- `goreleaser` - Release automation

### Formatting
- `gofumpt` - Stricter gofmt
- `golines` - Line length formatter

### Cloud Native
- `ko` - Kubernetes container builder
- `kind` - Kubernetes in Docker
- `grpcurl` - gRPC client
- `protoc-gen-go` - Protocol buffer compiler
- `protoc-gen-go-grpc` - gRPC code generator

### Utilities
- `hey` - HTTP load testing
- `yq` - YAML processor

## Common Commands

### Go Development
```bash
go mod init <module>
go mod tidy
go build
go test ./...
go run main.go
```

### Using Tools
```bash
# Format code
goimports -w .
gofumpt -w .

# Lint code
golangci-lint run

# Run tests with coverage
go test -cover ./...

# Live reload
air

# Debug
dlv debug

# Generate Swagger docs
swag init

# Load test
hey -n 1000 -c 10 http://localhost:8080
```

### Docker & Kubernetes
```bash
# Build with ko
ko build ./cmd/app

# Create local cluster
kind create cluster

# Deploy to cluster
kubectl apply -f k8s/

# Check cluster
kubectl get pods
```

## VSCode Extensions
The following extensions are pre-configured:
- `golang.go` - Official Go extension
- `GitHub.copilot` - AI pair programming
- `ms-azuretools.vscode-docker` - Docker support
- `ms-kubernetes-tools.vscode-kubernetes-tools` - Kubernetes
- `eamodio.gitlens` - Git visualization
- `hashicorp.terraform` - Infrastructure as Code

## Environment Variables
Set in docker-compose or .env file:
- `GOPATH=/go`
- `GOBIN=/go/bin`
- `PATH` includes Go binaries

## User Configuration
The container creates a user matching your host:
- Username: `${USER}` (e.g., brett)
- UID: `${UID}` (e.g., 1000)
- GID: `${GID}` (e.g., 1000)
- Shell: zsh with Oh My Zsh

## Updating Tools

### Update Go version
Edit Dockerfile line with `GO_VERSION="1.22.0"` and rebuild

### Update Go tools
```bash
# Inside container
go install golang.org/x/tools/gopls@latest
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
# ... repeat for other tools
```

## Troubleshooting

### Permission Issues
Ensure UID/GID match between host and container:
```bash
echo $UID $GID $USER
```

### Container Won't Start
Check logs:
```bash
docker logs go_bench
```

### Go Tools Not Found
Verify PATH includes Go bin directories:
```bash
echo $PATH | grep go
```

### Build Fails
Try clean build:
```bash
docker-compose down
docker system prune -a
docker-compose up -d --build
```

## Related Files
- `.devcontainer/Dockerfile` - Container definition
- `.devcontainer/devcontainer.json` - VSCode configuration
- `.devcontainer/docker-compose.yml` - Service definition
- `.devcontainer/.env.example` - Environment template
- `.devcontainer/AI_SETUP.md` - AI assistant setup
- `README.md` - User-facing documentation

## Layered Build Benefits

### Why Layered?
- **Faster rebuilds**: Only rebuild Go layer when needed
- **Shared base**: All benches share Layer 0 and Layer 1
- **Smaller images**: Layer 2 is only ~2GB
- **Better caching**: Docker caches unchanged layers

### Build Times
- **Layer 0** (workbench-base): 10-15 minutes (once)
- **Layer 1** (devbench-base): 5-10 minutes (once)
- **Layer 2** (go-bench): 5-8 minutes (rebuild as needed)
- **Subsequent starts**: < 30 seconds

## Notes
- Layered architecture is the new standard (as of Dec 2024)
- Legacy monolithic `.devcontainer/` is deprecated
- All tools are pre-installed for offline development
- User preferences: Layered Dockerfile at root, legacy in .devcontainer, warp.md in .warp
- Container size: ~4GB (Layer 2), ~8GB total (all layers)
