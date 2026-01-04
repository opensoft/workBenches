# 🚀 THE BIG HEAVY FULL LOADED GO DEVTOOL MONSTER

## Ubuntu 24.04 Go Development Container with Perfect UID/GID Matching

This is the **ultimate Go development container** - a massive, comprehensive Ubuntu 24.04-based devcontainer that includes **EVERYTHING** you could possibly need for modern Go development, with perfect user ID matching to your host system.

## 🎯 **Key Features**

### ✅ **Perfect User Management**
- **UID/GID matching** with your host system (crucial for WSL file permissions)
- No more permission issues with files created in the container
- Proper sudo access without password prompts

### 🏗️ **Based on Ubuntu 24.04**
- Latest Ubuntu LTS with all the newest packages
- Full control over package versions
- Optimized for WSL2 environments

## 🛠️ **THE MONSTER INCLUDES**

### **Core Development Stack**
- **Go 1.22+** (latest version)
- **25+ Go Development Tools** (gopls, delve, golangci-lint, etc.)
- **Docker & Docker Compose** 
- **Kubernetes** (kubectl, helm, kind)
- **Additional Language Runtimes**:
  - Node.js 20.x + npm
  - Python 3.12 + pip

### **Cloud & Infrastructure Tools**
- **Azure CLI**
- **Terraform** + **Pulumi** 
- **PowerShell** cross-platform

### **Modern CLI Experience**
- **Zsh with Oh My Zsh** + plugins (autosuggestions, syntax highlighting)
- **Starship prompt** for beautiful shell
- **Modern alternatives**: `exa`, `bat`, `ripgrep`, `fd`, `fzf`, `zoxide`
- **50+ useful aliases** pre-configured

### **Development Tools Galore**
- **Build tools**: cmake, ninja, gcc, clang, llvm
- **Debugging**: gdb, valgrind, strace, ltrace
- **Network tools**: nmap, netcat, tcpdump
- **Database clients**: PostgreSQL, MySQL, Redis, SQLite
- **Testing tools**: k6 load testing
- **Code quality**: staticcheck, golangci-lint, errcheck

### **VS Code Integration**
- **13 pre-installed extensions** including Go extension, Copilot, Docker
- **Optimized settings** for Go development
- **Port forwarding** for all common development servers

## 🚀 **Getting Started**

### **Option 1: VS Code (Recommended)**
1. Open this folder in VS Code
2. When prompted, click **"Reopen in Container"**
3. ☕ Grab coffee (first build takes 10-15 minutes)
4. 🎉 Start coding in your monster environment!

### **Option 2: Manual Docker Compose**
```bash
# Set environment variables
export UID=$(id -u) GID=$(id -g) USER=$(whoami)
cd .devcontainer
docker-compose up -d --build
```

## 📦 **What Gets Installed**

### **Go Development Tools (25+)**
```bash
gopls                    # Go Language Server
dlv                      # Delve debugger
golangci-lint           # Comprehensive linter
staticcheck             # Advanced static analysis
goimports               # Auto import management
gomodifytags            # Struct tag editor
gotests                 # Test generator
impl                    # Interface implementation generator
swag                    # Swagger documentation
air                     # Live reload
goreleaser              # Release automation
errcheck                # Error checking
gofumpt                 # Stricter gofmt
golines                 # Line length formatter
wire                    # Dependency injection
ko                      # Kubernetes builder
hey                     # HTTP load generator
grpcurl                 # gRPC client
protoc-gen-go           # Protocol buffer compiler
yq                      # YAML processor
kind                    # Kubernetes in Docker
# ... and more!
```

### **Language Runtimes & Package Managers**
```bash
Go 1.22+                # Latest Go
Node.js 20.x + npm      # JavaScript ecosystem  
Python 3.12 + pip       # Python development
```

### **Cloud & DevOps Tools**
```bash
Docker + Docker Compose # Containerization
Kubernetes (kubectl, helm, kind) # Container orchestration
Azure CLI               # Azure cloud
Terraform + Pulumi      # Infrastructure as Code
GitHub CLI              # GitHub integration
```

### **Modern CLI Tools**
```bash
exa        # Better ls
bat        # Better cat with syntax highlighting  
ripgrep    # Faster grep
fd         # Better find
fzf        # Fuzzy finder
zoxide     # Smarter cd
starship   # Beautiful prompt
k6         # Load testing
```

## 🎯 **Perfect for**
- **Go microservices** development
- **CLI tools** and utilities
- **Cloud-native applications** (Docker, Kubernetes)
- **API development** (REST, gRPC)
- **Infrastructure as Code** (Terraform, Pulumi)
- **Full-stack development** (Go backends with JavaScript frontends)

## ⚡ **Pre-configured Aliases**

```bash
# Go shortcuts
# (alias examples - these would be configured in shell)
go run, go build, go test, go mod, etc.

# Docker & Kubernetes  
d / dc / k                   # docker/docker-compose/kubectl
dps / kgp / kgs             # docker ps / kubectl get pods/services

# Modern CLI
ll / la / ls                # exa variants (better ls)
cat                         # bat (syntax highlighted)
find / grep                 # fd / ripgrep (faster)
cd                          # zoxide (smarter)
```

## 🌐 **Port Forwarding**
Auto-forwarded ports: `3000`, `8080`, `8081`, `9090`

## 📁 **Workspace Structure**
```
~/workspace/
├── src/         # Your source code
├── tests/       # Test projects  
├── docs/        # Documentation
├── scripts/     # Build scripts
├── tools/       # Custom tools
├── docker/      # Docker files
├── kubernetes/  # K8s manifests
└── terraform/   # Infrastructure code
```

## 🔧 **Container Specs**
- **Base**: Ubuntu 24.04 LTS (via workbench-base)
- **Layer 1**: devbench-base (Python, Node.js, AI tools)
- **Layer 2**: go-bench (Go 1.22+ and tools)
- **Size**: ~4GB (Layer 2 only)
- **Build time**: 5-8 minutes (Layer 2 only)
- **Subsequent starts**: <30 seconds
- **User mapping**: Perfect UID/GID match with host

## ⚠️ **System Requirements**
- **Docker Desktop** with WSL 2 backend
- **8GB+ RAM** allocated to Docker
- **15GB+ disk space** for the image
- **VS Code** with Remote-Containers extension

## 🎉 **Why This Approach?**

1. **Perfect Permission Mapping** - No more `chown` headaches
2. **Everything Pre-installed** - No waiting for tools during development  
3. **Consistent Environment** - Same setup across team members
4. **WSL Optimized** - Built specifically for WSL workflows
5. **Extensible** - Easy to add more tools to the Dockerfile

This is the container you use when you want **EVERYTHING** for Go development and don't want to think about setup ever again! 🚀

## 🔗 **Related DevBenches**

This goBench is part of the workBenches family:
- **dotNetBench** - .NET development
- **javaBench** - Java development
- **frappeBench** - Frappe/ERPNext development
- **pythonBench** - Python development
- **flutterBench** - Flutter development

All benches share the same network and can communicate with each other!
