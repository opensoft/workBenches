# sysBenches - Systems and Operations Workbenches

This folder contains individual systems and operations workbenches for infrastructure, cloud, deployment, and security workflows.

## Structure

Each subfolder is a separate git repository containing systems and operations tools:

- **`cloudBench/`** - Cloud infrastructure and Kubernetes operations
  - Azure Kubernetes Service (AKS) management
  - Kubernetes cluster configuration and tools
  - Database operations tools (SQL Server, PostgreSQL)
- **`opsBench/`** - Deployment, CI/CD, security, and GitOps operations

## Canonical Images

- **Layer 1b family base**: `sys-bench-base:latest`
- **Layer 2 benches**: `cloud-bench:latest`, `ops-bench:latest`
- **Layer 3 user images**: `<bench>:<user>` via `scripts/ensure-layer3.sh`

## Usage

### Using WorkBenches (Recommended)
```bash
# From workBenches root directory
./scripts/new-project.sh
```

### Direct Access
```bash
# Navigate to a specific sys bench
cd sysBenches/cloudBench
./build-layer.sh
```

## Adding New Sys Benches

Use the workBenches new-bench script:
```bash
# From workBenches root
./scripts/new-bench.sh
```

This can create additional systems and operations benches such as:
- Network administration tools
- Security management utilities  
- Monitoring and logging systems
- CI/CD pipeline management

## Organization

- **This folder** (`sysBenches/`) is part of the main workBenches repository
- **Individual benches** are separate git repositories
- **Each bench** provides specialized systems and operations tools for specific infrastructure domains

## Systems & Ops Domains

Systems and operations benches can cover various domains:
- **Cloud Infrastructure** - AWS, Azure, GCP management
- **Database Operations** - SQL Server, PostgreSQL, MongoDB
- **Container Orchestration** - Kubernetes, Docker Swarm
- **Networking** - DNS, load balancers, firewalls
- **Security** - Identity management, certificates, secrets
- **Monitoring** - Logging, metrics, alerting systems
