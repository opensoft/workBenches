# Flutter DevContainer Template Scripts

## 📋 Overview

This directory contains utility scripts for Flutter DevContainer project setup and validation.

## 🔧 Scripts

### `manual-setup-project.sh`

**Purpose**: Validates and sets up environment configuration for Flutter DevContainer projects when using manual template setup.

#### When To Use

✅ **Use this script when:**
- You manually copied the template files (instead of using `new-flutter-project.sh`)
- You're debugging container configuration issues
- You modified your `.env` file and want to validate the changes
- You're troubleshooting why your container won't build or start properly
- You want to understand what configuration is required

❌ **Don't use this script when:**
- You used `new-flutter-project.sh` (it handles setup automatically)
- Your container is already working fine
- You're just making code changes (not configuration changes)

#### What It Does

1. **🔍 Environment File Management**
   - Creates `.env` from `.env.example` if missing
   - Validates all required environment variables are set
   - Checks for proper variable formats and values

2. **✅ Configuration Validation**
   - Ensures `PROJECT_NAME` uses valid characters only
   - Verifies `USER_UID`/`USER_GID` are numeric and match your system
   - Validates `FLUTTER_VERSION` and other required settings

3. **🏗️ Infrastructure Checks**
   - Verifies shared ADB infrastructure path exists
   - Provides guidance if infrastructure is missing

4. **🐳 Docker Environment**
   - Confirms Docker is installed and running
   - Tests Docker Compose configuration syntax
   - Validates container can be built with current settings

5. **📋 Guidance & Summary**
   - Shows final configuration summary
   - Provides next steps for container development
   - Offers troubleshooting tips

#### How To Use

##### Basic Usage
```bash
# Navigate to your Flutter project directory
cd ~/projects/my-flutter-app

# Run the validation script
./scripts/manual-setup-project.sh
```

##### Typical Workflow - Manual Template Setup
```bash
# 1. Create Flutter project
flutter create my-flutter-app
cd my-flutter-app

# 2. Copy template files manually
cp -r path/to/template/.devcontainer .
cp -r path/to/template/.vscode .
cp -r path/to/template/scripts .
cp path/to/template/docker-compose.yml .
cp path/to/template/Dockerfile .
cp path/to/template/.env.example .

# 3. Create and edit environment file
cp .env.example .env
# Edit .env file with your settings...

# 4. Validate setup (THIS SCRIPT)
./scripts/manual-setup-project.sh
```

##### Debugging Workflow
```bash
# Container won't start? Check configuration
./scripts/manual-setup-project.sh

# Made changes to .env? Validate them
nano .env  # or your preferred editor
./scripts/manual-setup-project.sh

# Getting permission errors? Check UID/GID
id  # Check your current UID/GID
# Edit .env to match your UID/GID
./scripts/manual-setup-project.sh
```

#### Sample Output

```
🔍 Flutter DevContainer Environment Setup
========================================

✅ Found .env file
🔍 Validating environment variables...
✅ All required variables found in .env
🔍 Validating variable values...
✅ Variable values validated
🔍 Validating infrastructure path...
✅ Infrastructure script found: ../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
🔍 Checking Docker environment...
✅ Docker environment ready
🔍 Testing Docker Compose configuration...
✅ Docker Compose configuration valid

🎉 Environment validation complete!

📋 Configuration Summary:
   Project Name: my-flutter-app
   User: developer (1000:1000)
   Flutter Version: 3.24.0
   Container Name: my-flutter-app-dev

✅ Your Flutter DevContainer environment is ready!

🚀 Next steps:
   1. Open this project in VS Code: code .
   2. Click 'Reopen in Container' when prompted
   3. Wait for container to build and start
   4. Start coding!
```

#### Common Issues & Solutions

##### Missing .env File
```
⚠️  .env file not found!
📋 Creating .env from .env.example...
✅ Created .env file

📝 Please edit .env and set the following variables:
   - PROJECT_NAME (currently: myproject)
   - USER_UID (currently: 1000)
   - USER_GID (currently: 1000)

💡 Tip: Run 'id' to check your current UID and GID
💡 Tip: Run this script again after editing .env
```

**Solution**: Edit the created `.env` file with your settings, then run the script again.

##### UID/GID Mismatch
```
⚠️  User ID mismatch detected:
   .env UID:GID = 1000:1000
   Your UID:GID = 1001:1001

💡 For best file permissions, consider updating .env:
   USER_UID=1001
   USER_GID=1001
```

**Solution**: Update your `.env` file with the correct UID/GID values.

##### Invalid Project Name
```
❌ PROJECT_NAME contains invalid characters
   Current: my flutter app
   Must contain only letters, numbers, underscores, and hyphens
```

**Solution**: Change `PROJECT_NAME` in `.env` to use only valid characters (e.g., `my-flutter-app`).

##### Docker Not Running
```
❌ Docker daemon not running
   Please start Docker Desktop or Docker service
```

**Solution**: Start Docker Desktop (Windows/Mac) or Docker service (Linux).

## 🔄 Comparison: Manual vs Automated Setup

### Automated Setup (`new-flutter-project.sh`)
✅ **Pros:**
- Handles everything automatically
- Creates Flutter project + DevContainer setup
- No validation needed
- Best for new projects

❌ **Cons:**
- Less control over the process
- Must use specific directory structure
- Can't customize template before applying

### Manual Setup (+ `manual-setup-project.sh`)
✅ **Pros:**
- Full control over template customization
- Can apply to existing projects
- Can modify template before copying
- Better for learning/understanding

❌ **Cons:**
- More steps required
- Need to validate configuration manually
- Easy to miss required steps

## 💡 Tips

- **Always run the validation script** after manual setup
- **Check your UID/GID** with `id` command before setting up
- **Keep `.env.example` in version control** but not `.env`
- **Use descriptive project names** (no spaces or special characters)
- **Run validation again** after making configuration changes