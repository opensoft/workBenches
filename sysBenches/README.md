# adminBenches - Administrative Workbenches

This folder contains individual administrative workbenches for different infrastructure and database management systems.

## Structure

Each subfolder is a separate git repository containing administrative tools and utilities:

- **`cloudAdmin/`** - Cloud infrastructure and Kubernetes administration
  - Azure Kubernetes Service (AKS) management
  - Kubernetes cluster configuration and tools
  - Database administration tools (SQL Server, PostgreSQL)

## Usage

### Using WorkBenches (Recommended)
```bash
# From workBenches root directory
./scripts/new-project.sh
```

### Direct Access
```bash
# Navigate to specific admin bench
cd adminBenches/cloudAdmin
# Use administrative tools and configurations
```

## Adding New Administrative Benches

Use the workBenches new-bench script:
```bash
# From workBenches root
./scripts/new-bench.sh
```

This can create additional administrative benches such as:
- Network administration tools
- Security management utilities  
- Monitoring and logging systems
- CI/CD pipeline management

## Organization

- **This folder** (`adminBenches/`) is part of the main workBenches repository
- **Individual benches** are separate git repositories
- **Each bench** provides specialized administrative tools for specific infrastructure domains

## Administrative Domains

Administrative benches can cover various domains:
- **Cloud Infrastructure** - AWS, Azure, GCP management
- **Database Administration** - SQL Server, PostgreSQL, MongoDB
- **Container Orchestration** - Kubernetes, Docker Swarm
- **Networking** - DNS, load balancers, firewalls
- **Security** - Identity management, certificates, secrets
- **Monitoring** - Logging, metrics, alerting systems