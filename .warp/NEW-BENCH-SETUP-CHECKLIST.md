# New Bench Type Setup Checklist

Use this checklist when creating a new Bench type (e.g., FlutterBench, ReactBench, etc.)

## Prerequisites
- [ ] Generic `devcontainer.example/` template exists at `/home/brett/projects/workBenches/devcontainer.example/`
- [ ] frappeBench workspace setup as reference at `/home/brett/projects/workBenches/devBenches/frappeBench/`

## Step 1: Create Project Structure

```bash
mkdir -p /home/brett/projects/workBenches/devBenches/{YourBench}
mkdir -p /home/brett/projects/workBenches/devBenches/{YourBench}/scripts/lib
mkdir -p /home/brett/projects/workBenches/devBenches/{YourBench}/workspaces
mkdir -p /home/brett/projects/workBenches/devBenches/{YourBench}/.warp
```

- [ ] Created project root directory
- [ ] Created scripts directory
- [ ] Created workspaces directory
- [ ] Created .warp directory

## Step 2: Copy Generic Template

```bash
cp -r /home/brett/projects/workBenches/devcontainer.example \
  /home/brett/projects/workBenches/devBenches/{YourBench}/devcontainer.example
```

- [ ] Copied `devcontainer.example/` to project
- [ ] Verified all files copied (Dockerfile, devcontainer.json, docker-compose.yml, etc.)

## Step 3: Create Framework-Specific Setup Script

**Source**: `devBenches/frappeBench/setup.sh`

Adapt for your framework:

```bash
cp /home/brett/projects/workBenches/devBenches/frappeBench/setup.sh \
  /home/brett/projects/workBenches/devBenches/{YourBench}/setup.sh

# Edit setup.sh to:
# - Change workspace script name references
# - Update help text for framework
# - Adjust version checking as needed
```

- [ ] Created `setup.sh`
- [ ] Updated script references for your framework
- [ ] Updated documentation strings

## Step 4: Create Workspace Creation Script

**Source**: `devBenches/frappeBench/scripts/new-frappe-workspace.sh`

Create workspace script for your framework:

```bash
cp /home/brett/projects/workBenches/devBenches/frappeBench/scripts/new-frappe-workspace.sh \
  /home/brett/projects/workBenches/devBenches/{YourBench}/scripts/new-{your-bench}-workspace.sh
```

Customize:
- [ ] Update function names and descriptions
- [ ] Modify docker-compose.override.yml generation for framework services
- [ ] Set framework-specific environment variables in `.env` file
- [ ] Adjust port numbering scheme if needed
- [ ] Update APP_REPO detection for your framework

## Step 5: Create Workspace Deletion Script

**Source**: `devBenches/frappeBench/scripts/delete-frappe-workspace.sh`

```bash
cp /home/brett/projects/workBenches/devBenches/frappeBench/scripts/delete-frappe-workspace.sh \
  /home/brett/projects/workBenches/devBenches/{YourBench}/scripts/delete-{your-bench}-workspace.sh
```

- [ ] Copied deletion script
- [ ] Updated variable names

## Step 6: Customize devcontainer.example

### docker-compose.yml
- [ ] Review generic docker-compose.yml
- [ ] Add framework-specific services if needed (database, cache, etc.)
- [ ] Update environment variables section with framework requirements

### docker-compose.override.example.yml
- [ ] Create template showing how to add framework services
- [ ] Document required services for your framework

### Dockerfile
- [ ] Review generic Dockerfile (should be sufficient for most frameworks)
- [ ] If framework requires additional build tools, extend as needed
- [ ] Keep AI assistant CLIs (Claude, Codex, etc.)

### devcontainer.json
- [ ] Update extension recommendations if needed (framework-specific)
- [ ] Adjust post-create/start commands for framework initialization
- [ ] Update README with framework-specific notes

### .env and .env.example
- [ ] Update `.env.example` with framework-specific variables
- [ ] Document all configuration options
- [ ] Include examples for common setups

### README.md
- [ ] Update for your framework specifics
- [ ] Add sections for framework-specific customization
- [ ] Document included tools relevant to framework

## Step 7: Create Common Utility Scripts

**Source**: `devBenches/frappeBench/scripts/lib/`

Copy utility libraries:
```bash
cp -r /home/brett/projects/workBenches/devBenches/frappeBench/scripts/lib \
  /home/brett/projects/workBenches/devBenches/{YourBench}/scripts/
```

- [ ] Copied utility scripts
- [ ] Reviewed `common.sh` for reusability
- [ ] Reviewed `git-project.sh` for project detection
- [ ] Reviewed `ai-assistant.sh` for AI integration

## Step 8: Create Documentation

**Files to create**:

### `.warp/workspace-setup.md`
Copy from frappeBench and adapt:

- [ ] Describe workspace creation system
- [ ] Update framework-specific examples
- [ ] Document environment variables
- [ ] Add usage instructions

### `.warp/{YourBench}-specific.md`
Create framework-specific documentation:

- [ ] Development workflow for framework
- [ ] Framework prerequisites
- [ ] Troubleshooting guide
- [ ] Extension points for customization

## Step 9: Testing

### Initial Setup
```bash
cd /home/brett/projects/workBenches/devBenches/{YourBench}
bash setup.sh
```

- [ ] Setup script runs without errors
- [ ] Alpha workspace created successfully
- [ ] `.devcontainer/` folder exists in workspace

### Workspace Creation
```bash
cd /home/brett/projects/workBenches/devBenches/{YourBench}
./scripts/new-{your-bench}-workspace.sh bravo
```

- [ ] Second workspace created successfully
- [ ] Each workspace gets unique port
- [ ] Each workspace gets unique container name
- [ ] `.env` file correctly customized per workspace

### Container Launch (Optional)
```bash
cd workspaces/alpha
code .
```

- [ ] VSCode opens workspace
- [ ] "Reopen in Container" option appears
- [ ] Container builds without errors (takes first time)
- [ ] Framework tools available in container

## Step 10: Documentation Updates

- [ ] Create summary document in `.warp/`
- [ ] Update main README to mention new Bench type
- [ ] Document any framework-specific requirements
- [ ] Add to known Bench types list

## Quick Reference

### Files Modified/Created

```
{YourBench}/
├── .warp/
│   ├── workspace-setup.md           (NEW)
│   └── {your-bench}-specific.md     (NEW)
├── devcontainer.example/            (COPIED & MODIFIED)
│   ├── Dockerfile                   (MAYBE MODIFIED)
│   ├── docker-compose.yml           (MAYBE MODIFIED)
│   ├── docker-compose.override.example.yml (NEW)
│   ├── devcontainer.json            (MAYBE MODIFIED)
│   ├── .env                         (MODIFIED)
│   ├── .env.example                 (MODIFIED)
│   └── README.md                    (MODIFIED)
├── scripts/
│   ├── lib/                         (COPIED)
│   ├── new-{your-bench}-workspace.sh (NEW)
│   ├── delete-{your-bench}-workspace.sh (NEW)
│   └── ...other scripts
├── workspaces/                      (DIRECTORY ONLY)
├── setup.sh                         (NEW)
└── README.md                        (NEW)
```

## Common Pitfalls to Avoid

- ❌ Hardcoding framework names in generic template
- ❌ Forgetting to update all script variable names
- ❌ Not updating `docker-compose.override.example.yml`
- ❌ Skipping documentation
- ❌ Not testing workspace creation before publishing

## Support References

- Generic template: `/home/brett/projects/workBenches/devcontainer.example/`
- Generic template docs: `/home/brett/projects/workBenches/.warp/generic-devcontainer-template.md`
- Reference implementation: `/home/brett/projects/workBenches/devBenches/frappeBench/`
- Workspace setup pattern: `/home/brett/projects/dartwing/frappe/` (original dartwing)

## Next: Adding to CI/CD (Optional)

- [ ] Create GitHub Actions workflow for testing new Bench types
- [ ] Add Bench type to supported list in documentation
- [ ] Create templates for IDE configurations if needed
