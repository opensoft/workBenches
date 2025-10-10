# 🚀 THE BIG HEAVY FULL LOADED DEVTOOL MONSTER

## Ubuntu 24.04 .NET Development Container with Perfect UID/GID Matching

This is the **ultimate .NET development container** - a massive, comprehensive Ubuntu 24.04-based devcontainer that includes **EVERYTHING** you could possibly need for modern .NET development, with perfect user ID matching to your host system.

## 🎯 **Key Features**

### ✅ **Perfect User Management**
- **UID/GID matching** with your host system (crucial for WSL file permissions)
- No more permission issues with files created in the container
- Proper sudo access without password prompts

### 🏗️ **Based on Ubuntu 24.04**
- Latest Ubuntu LTS with all the newest packages
- Built from scratch as a custom Dockerfile (not a pre-built image)
- Full control over every component

## �️ **THE MONSTER INCLUDES**

### **Core Development Stack**
- **.NET 8.0 SDK** with ALL workloads (Blazor, MAUI, Android, iOS, etc.)
- **25+ .NET Global Tools** (EF Core, testing, profiling, code analysis)
- **Docker & Docker Compose** 
- **Kubernetes** (kubectl, helm, tilt)
- **Multiple Language Runtimes**:
  - Node.js 20.x + npm + bun + deno
  - Python 3.12 + pip + JupyterLab
  - Java 21, 17, 11 JDKs
  - Go language
  - Rust + Cargo

### **Cloud & Infrastructure Tools**
- **Azure CLI** with Bicep
- **Terraform** + **Pulumi** 
- **Dapr CLI** for microservices
- **PowerShell** cross-platform

### **Modern CLI Experience**
- **Zsh with Oh My Zsh** + plugins (autosuggestions, syntax highlighting)
- **Starship prompt** for beautiful shell
- **Modern alternatives**: `exa`, `bat`, `ripgrep`, `fd`, `fzf`, `zoxide`
- **50+ useful aliases** pre-configured

### **Development Tools Galore**
- **Build tools**: cmake, ninja, gcc, clang, llvm
- **Debugging**: gdb, valgrind, strace, ltrace
- **Network tools**: nmap, netcat, wireshark, tcpdump
- **Database clients**: PostgreSQL, MySQL, Redis, SQLite
- **Testing tools**: k6 load testing, Playwright
- **Code quality**: SonarScanner, mutation testing
- **Performance**: profiling, monitoring, benchmarking tools

### **VS Code Integration**
- **19 pre-installed extensions** including C# Dev Kit, Copilot, Docker
- **Optimized settings** for .NET development
- **Port forwarding** for all common development servers

## 🚀 **Getting Started**

### **Option 1: VS Code (Recommended)**
1. Open this folder in VS Code
2. When prompted, click **"Reopen in Container"**
3. ☕ Grab coffee (first build takes 10-15 minutes)
4. 🎉 Start coding in your monster environment!

### **Option 2: Manual Docker Compose**
```bash
# Run the helper script to get your UID/GID
./scripts/start-monster.sh

# Or manually with docker-compose
export UID=$(id -u) GID=$(id -g) USER=$(whoami)
docker-compose -f .devcontainer/docker-compose.yml up -d --build
```

## 📦 **What Gets Installed**

### **.NET Global Tools (25+)**
```bash
dotnet-ef                    # Entity Framework
dotnet-aspnet-codegenerator  # ASP.NET scaffolding
dotnet-stryker              # Mutation testing
dotnet-reportgenerator      # Code coverage
dotnet-outdated             # Dependency updates
GitVersion.Tool             # Semantic versioning
Microsoft.Tye               # Microservices dev
dotnet-trace                # Performance profiling
dotnet-dump                 # Memory analysis
dotnet-monitor              # Diagnostic monitoring
PowerShell                  # Cross-platform PS
# ... and 15 more!
```

### **Language Runtimes & Package Managers**
```bash
.NET 8.0 SDK               # Latest .NET
Node.js 20.x + npm         # JavaScript ecosystem  
Python 3.12 + pip          # Python development
Java 21/17/11 JDKs         # Multi-Java support
Go                         # Go language
Rust + Cargo               # Systems programming
Bun                        # Fast JS runtime
Deno                       # Modern JS runtime
```

### **Cloud & DevOps Tools**
```bash
Docker + Docker Compose    # Containerization
Kubernetes (kubectl, helm) # Container orchestration
Azure CLI + Bicep          # Azure cloud
Terraform + Pulumi         # Infrastructure as Code
Dapr CLI                   # Microservices runtime
GitHub CLI                 # GitHub integration
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
hyperfine  # Benchmarking
tokei      # Code statistics
just       # Command runner
```

## 🎯 **Perfect for**
- **.NET Core/Framework** development
- **Blazor** applications (Server, WebAssembly, Hybrid)
- **ASP.NET Core** APIs and web apps
- **MAUI** cross-platform apps
- **Microservices** architecture (with Dapr, Docker, K8s)
- **Cloud development** (Azure, containers, serverless)
- **Full-stack development** (React, Angular, Vue with .NET backends)

## ⚡ **Pre-configured Aliases**

```bash
# .NET shortcuts
dn / dnr / dnb / dnt / dnw   # dotnet run/build/test/watch
dnef                         # dotnet ef

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
Auto-forwarded ports: `3000`, `4200`, `5000`, `5001`, `7071`, `8080`

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
- **Base**: Ubuntu 24.04 LTS
- **Size**: ~8GB (it's a monster!)
- **Build time**: 10-15 minutes first time
- **Subsequent starts**: <30 seconds
- **User mapping**: Perfect UID/GID match with host

## ⚠️ **System Requirements**
- **Docker Desktop** with WSL 2 backend
- **8GB+ RAM** allocated to Docker
- **20GB+ disk space** for the image
- **VS Code** with Remote-Containers extension

## 🎉 **Why This Approach?**

1. **Perfect Permission Mapping** - No more `chown` headaches
2. **Everything Pre-installed** - No waiting for tools during development  
3. **Consistent Environment** - Same setup across team members
4. **WSL Optimized** - Built specifically for WSL workflows
5. **Extensible** - Easy to add more tools to the Dockerfile

This is the container you use when you want **EVERYTHING** and don't want to think about setup ever again! 🚀