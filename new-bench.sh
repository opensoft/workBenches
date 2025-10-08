#!/bin/bash

# WorkBenches New Bench Creation Script
# Creates new development benches with AI-powered tech stack discovery

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/bench-config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default tech stacks (fallback if AI unavailable)
DEFAULT_TECH_STACKS='[
  {
    "name": "go",
    "display_name": "Go",
    "description": "Modern systems programming language by Google",
    "frameworks": ["Gin", "Echo", "Fiber", "Buffalo", "Revel"],
    "tools": ["go mod", "gofmt", "golint", "gopls"],
    "container_base": "golang:1.21-alpine"
  },
  {
    "name": "rust",
    "display_name": "Rust",
    "description": "Systems programming language focused on safety and performance",
    "frameworks": ["Axum", "Actix", "Warp", "Rocket", "Tauri"],
    "tools": ["cargo", "rustfmt", "clippy", "rust-analyzer"],
    "container_base": "rust:1.70-alpine"
  },
  {
    "name": "node",
    "display_name": "Node.js",
    "description": "JavaScript runtime for server-side development",
    "frameworks": ["Express", "Fastify", "NestJS", "Koa", "Next.js", "Nuxt"],
    "tools": ["npm", "yarn", "pnpm", "tsx", "nodemon"],
    "container_base": "node:18-alpine"
  },
  {
    "name": "php",
    "display_name": "PHP",
    "description": "Popular web development language",
    "frameworks": ["Laravel", "Symfony", "CodeIgniter", "Slim", "Phalcon"],
    "tools": ["composer", "php-cs-fixer", "phpstan", "psalm"],
    "container_base": "php:8.2-fpm-alpine"
  },
  {
    "name": "ruby",
    "display_name": "Ruby",
    "description": "Dynamic programming language focused on developer happiness",
    "frameworks": ["Ruby on Rails", "Sinatra", "Hanami", "Roda", "Cuba"],
    "tools": ["bundler", "rubocop", "rspec", "minitest"],
    "container_base": "ruby:3.2-alpine"
  },
  {
    "name": "kotlin",
    "display_name": "Kotlin",
    "description": "Modern JVM language by JetBrains",
    "frameworks": ["Spring Boot", "Ktor", "Quarkus", "Micronaut", "Javalin"],
    "tools": ["gradle", "maven", "ktlint", "detekt"],
    "container_base": "openjdk:17-jdk-alpine"
  },
  {
    "name": "swift",
    "display_name": "Swift",
    "description": "Apple programming language for iOS/macOS and server development",
    "frameworks": ["Vapor", "Perfect", "Kitura", "SwiftUI", "Combine"],
    "tools": ["swift package manager", "swiftformat", "swiftlint"],
    "container_base": "swift:5.8-focal"
  },
  {
    "name": "scala",
    "display_name": "Scala",
    "description": "Functional and object-oriented JVM language",
    "frameworks": ["Akka", "Play", "Cats Effect", "ZIO", "Finch"],
    "tools": ["sbt", "mill", "scalafmt", "scalafix"],
    "container_base": "openjdk:17-jdk-alpine"
  }
]'

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and run again."
        echo ""
        echo "On Ubuntu/Debian: sudo apt install ${missing_deps[*]}"
        echo "On macOS: brew install ${missing_deps[*]}"
        exit 1
    fi
}

# Connect to OpenAI API for tech stack information
query_openai_api() {
    local prompt="$1"
    local api_key="$OPENAI_API_KEY"
    
    if [ -z "$api_key" ]; then
        return 1
    fi
    
    local response
    response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"gpt-4o-mini\",
            \"messages\": [
                {
                    \"role\": \"system\",
                    \"content\": \"You are a tech stack expert. Respond only with valid JSON. No explanations, just the requested JSON data.\"
                },
                {
                    \"role\": \"user\",
                    \"content\": \"$prompt\"
                }
            ],
            \"max_tokens\": 2000,
            \"temperature\": 0.1
        }")
    
    if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        echo "$response" | jq -r '.choices[0].message.content'
        return 0
    else
        return 1
    fi
}

# Connect to Claude API for tech stack information
query_claude_api() {
    local prompt="$1"
    local api_key="$ANTHROPIC_API_KEY"
    
    if [ -z "$api_key" ]; then
        return 1
    fi
    
    local response
    response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $api_key" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-3-haiku-20240307\",
            \"max_tokens\": 2000,
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": \"You are a tech stack expert. Respond only with valid JSON. No explanations, just the requested JSON data. $prompt\"
                }
            ]
        }")
    
    if echo "$response" | jq -e '.content[0].text' >/dev/null 2>&1; then
        echo "$response" | jq -r '.content[0].text'
        return 0
    else
        return 1
    fi
}

# Get current tech stack information from AI
get_ai_tech_stacks() {
    echo -e "${CYAN}🤖 Querying AI for current tech stack information...${NC}"
    
    local prompt='Return a JSON array of current popular programming languages and frameworks for development in 2024. For each language, include: name (lowercase), display_name, description, popular frameworks array, essential tools array, and recommended Docker container_base. Focus on languages suitable for creating development environments. Return exactly this format:
[
  {
    "name": "go",
    "display_name": "Go", 
    "description": "Brief description",
    "frameworks": ["Framework1", "Framework2"],
    "tools": ["tool1", "tool2"],
    "container_base": "image:tag"
  }
]'
    
    local ai_response=""
    
    # Try OpenAI first
    if [ -n "$OPENAI_API_KEY" ]; then
        echo -e "  ${YELLOW}Trying OpenAI API...${NC}"
        ai_response=$(query_openai_api "$prompt" 2>/dev/null || echo "")
    fi
    
    # Try Claude if OpenAI failed
    if [ -z "$ai_response" ] && [ -n "$ANTHROPIC_API_KEY" ]; then
        echo -e "  ${YELLOW}Trying Claude API...${NC}"
        ai_response=$(query_claude_api "$prompt" 2>/dev/null || echo "")
    fi
    
    # Validate and return AI response or fallback
    if [ -n "$ai_response" ] && echo "$ai_response" | jq . >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Got current tech stack info from AI${NC}"
        echo "$ai_response"
    else
        echo -e "  ${YELLOW}⚠ Using default tech stack list (AI unavailable)${NC}"
        echo "$DEFAULT_TECH_STACKS"
    fi
}

# Display available tech stacks
show_tech_stacks() {
    local tech_stacks="$1"
    echo -e "${YELLOW}Available tech stacks:${NC}"
    echo ""
    
    local counter=1
    echo "$tech_stacks" | jq -r '.[] | @base64' | while read -r stack_data; do
        local stack=$(echo "$stack_data" | base64 -d)
        local name=$(echo "$stack" | jq -r '.name')
        local display_name=$(echo "$stack" | jq -r '.display_name')
        local description=$(echo "$stack" | jq -r '.description')
        local frameworks=$(echo "$stack" | jq -r '.frameworks | join(", ")')
        
        echo -e "${BLUE}$counter) $display_name${NC} ($name)"
        echo -e "   ${description}"
        echo -e "   ${CYAN}Frameworks: ${frameworks}${NC}"
        echo ""
        ((counter++))
    done
}

# Select tech stack
select_tech_stack() {
    local tech_stacks="$1"
    local stack_count=$(echo "$tech_stacks" | jq length)
    
    while true; do
        echo "Enter the number of your choice, or 'c' for custom:"
        read -p "Choice (1-$stack_count or 'c'): " choice
        
        if [ "$choice" = "c" ] || [ "$choice" = "C" ]; then
            create_custom_tech_stack
            return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$stack_count" ]; then
            local selected_stack=$(echo "$tech_stacks" | jq ".[$((choice-1))]")
            process_selected_stack "$selected_stack"
            return
        else
            echo -e "${RED}Invalid choice. Please enter 1-$stack_count or 'c'.${NC}"
        fi
    done
}

# Create custom tech stack
create_custom_tech_stack() {
    echo -e "${MAGENTA}Creating custom tech stack...${NC}"
    echo ""
    
    read -p "Language/Technology name (lowercase): " tech_name
    read -p "Display name: " display_name
    read -p "Description: " description
    read -p "Main frameworks (comma-separated): " frameworks_input
    read -p "Essential tools (comma-separated): " tools_input
    read -p "Docker base image (e.g., alpine:latest): " container_base
    
    # Convert comma-separated to JSON arrays
    local frameworks_array=$(echo "\"$frameworks_input\"" | sed 's/, */", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    local tools_array=$(echo "\"$tools_input\"" | sed 's/, */", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    
    local custom_stack="{
        \"name\": \"$tech_name\",
        \"display_name\": \"$display_name\",
        \"description\": \"$description\",
        \"frameworks\": $frameworks_array,
        \"tools\": $tools_array,
        \"container_base\": \"$container_base\"
    }"
    
    echo ""
    echo -e "${GREEN}Custom tech stack created:${NC}"
    echo "$custom_stack" | jq .
    echo ""
    
    read -p "Does this look correct? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Let's try again..."
        create_custom_tech_stack
        return
    fi
    
    process_selected_stack "$custom_stack"
}

# Process selected tech stack and create bench
process_selected_stack() {
    local stack="$1"
    local tech_name=$(echo "$stack" | jq -r '.name')
    local display_name=$(echo "$stack" | jq -r '.display_name')
    local description=$(echo "$stack" | jq -r '.description')
    local frameworks=$(echo "$stack" | jq -r '.frameworks[]' | tr '\n' ' ')
    local tools=$(echo "$stack" | jq -r '.tools[]' | tr '\n' ' ')
    local container_base=$(echo "$stack" | jq -r '.container_base')
    
    echo ""
    echo -e "${GREEN}Selected: $display_name${NC}"
    echo ""
    
    # Get bench name
    local default_bench_name="${tech_name}Bench"
    read -p "Bench name [$default_bench_name]: " bench_name
    bench_name="${bench_name:-$default_bench_name}"
    
    # Determine bench path
    local bench_path="devBench/$bench_name"
    if [ -d "$SCRIPT_DIR/$bench_path" ]; then
        echo -e "${RED}Error: Bench already exists at $bench_path${NC}"
        exit 1
    fi
    
    # Get repository URL (optional)
    echo ""
    echo "Repository URL (optional - leave empty for local-only bench):"
    read -p "Git repository URL: " repo_url
    
    echo ""
    echo -e "${BLUE}Creating $bench_name bench...${NC}"
    echo -e "${BLUE}Technology: $display_name${NC}"
    echo -e "${BLUE}Path: $bench_path${NC}"
    echo -e "${BLUE}Container Base: $container_base${NC}"
    echo ""
    
    create_bench_structure "$bench_path" "$stack" "$repo_url"
}

# Create the actual bench directory structure
create_bench_structure() {
    local bench_path="$1"
    local stack="$2"
    local repo_url="$3"
    
    local tech_name=$(echo "$stack" | jq -r '.name')
    local display_name=$(echo "$stack" | jq -r '.display_name')
    local description=$(echo "$stack" | jq -r '.description')
    local container_base=$(echo "$stack" | jq -r '.container_base')
    
    # Create directory structure
    echo -e "${CYAN}📁 Creating directory structure...${NC}"
    mkdir -p "$SCRIPT_DIR/$bench_path"/{.devcontainer,.vscode,scripts,templates,docs}
    
    cd "$SCRIPT_DIR/$bench_path"
    
    # Initialize git repository
    echo -e "${CYAN}📦 Initializing git repository...${NC}"
    git init
    
    if [ -n "$repo_url" ]; then
        git remote add origin "$repo_url"
    fi
    
    # Create README.md
    echo -e "${CYAN}📝 Creating README.md...${NC}"
    cat > README.md << EOF
# $display_name Development Bench

$description

## Quick Start

### Using DevContainer (Recommended)
1. Open this directory in VS Code
2. Click "Reopen in Container" when prompted
3. Wait for container to build
4. Start developing!

### Manual Setup
1. Install $display_name and required tools
2. Run the setup scripts in \`scripts/\`
3. Use project templates in \`templates/\`

## What's Included

- **DevContainer**: Pre-configured development environment
- **VS Code**: Optimized settings and extensions
- **Project Templates**: Ready-to-use starter projects
- **Scripts**: Automation for common tasks

## Creating New Projects

### Using WorkBenches (Recommended)
\`\`\`bash
# From workBenches root directory
./new-project.sh
\`\`\`

### Direct Script Usage
\`\`\`bash
# From this bench directory
./scripts/new-${tech_name}-project.sh <project-name> [target-directory]
\`\`\`

## Technologies & Frameworks

This bench supports:
$(echo "$stack" | jq -r '.frameworks[]' | sed 's/^/- /')

## Tools Included

$(echo "$stack" | jq -r '.tools[]' | sed 's/^/- /')

## Documentation

- [Setup Guide](docs/setup.md)
- [Project Templates](docs/templates.md)
- [DevContainer Guide](docs/devcontainer.md)

## Contributing

Contributions are welcome! Please read our contributing guidelines.
EOF
    
    # Create .gitignore
    echo -e "${CYAN}📝 Creating .gitignore...${NC}"
    cat > .gitignore << EOF
# $display_name specific
*.log
*.tmp
.env
.env.local
.env.*.local

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db

# Dependencies
node_modules/
vendor/
target/
dist/
build/

# DevContainer
.devcontainer/docker-compose.override.yml
EOF
    
    # Create DevContainer configuration
    echo -e "${CYAN}🐳 Creating DevContainer configuration...${NC}"
    cat > .devcontainer/devcontainer.json << EOF
{
    "name": "$display_name Development",
    "image": "$container_base",
    
    "customizations": {
        "vscode": {
            "settings": {
                "terminal.integrated.shell.linux": "/bin/bash"
            },
            "extensions": [
                "ms-vscode.vscode-json",
                "ms-vscode.extension-test-runner",
                "github.copilot",
                "github.copilot-chat"
            ]
        }
    },
    
    "features": {
        "ghcr.io/devcontainers/features/common-utils:2": {
            "installZsh": true,
            "installOhMyZsh": true,
            "upgradePackages": true,
            "username": "vscode",
            "userUid": "automatic",
            "userGid": "automatic"
        },
        "ghcr.io/devcontainers/features/git:1": {
            "version": "latest",
            "ppa": true
        }
    },
    
    "postCreateCommand": "bash .devcontainer/post-create.sh",
    
    "remoteUser": "vscode",
    
    "mounts": [
        "source=\${localWorkspaceFolder}/.vscode,target=/workspace/.vscode,type=bind"
    ]
}
EOF
    
    # Create post-create script
    echo -e "${CYAN}🔧 Creating post-create script...${NC}"
    cat > .devcontainer/post-create.sh << 'EOF'
#!/bin/bash

# Post-creation setup for development environment

echo "🚀 Setting up development environment..."

# Update package lists
sudo apt-get update

# Install common development tools
sudo apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    build-essential \
    jq

# Set up git (if not already configured)
if [ -z "$(git config --global user.name)" ]; then
    echo "⚠️  Git not configured. Please run:"
    echo "   git config --global user.name 'Your Name'"
    echo "   git config --global user.email 'your.email@example.com'"
fi

echo "✅ Development environment setup complete!"
echo ""
echo "🎯 Next steps:"
echo "   1. Configure your development tools"
echo "   2. Review the README.md for guidance"
echo "   3. Start building amazing things!"

EOF
    chmod +x .devcontainer/post-create.sh
    
    # Create VS Code settings
    echo -e "${CYAN}⚙️ Creating VS Code settings...${NC}"
    cat > .vscode/settings.json << EOF
{
    "files.exclude": {
        "**/.git": true,
        "**/node_modules": true,
        "**/target": true,
        "**/dist": true,
        "**/build": true
    },
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
        "source.fixAll": true,
        "source.organizeImports": true
    },
    "terminal.integrated.defaultProfile.linux": "bash",
    "git.autofetch": true
}
EOF
    
    # Create launch configuration
    cat > .vscode/launch.json << EOF
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug $display_name Application",
            "type": "node",
            "request": "launch",
            "program": "\${workspaceFolder}/src/main.js",
            "console": "integratedTerminal",
            "internalConsoleOptions": "neverOpen"
        }
    ]
}
EOF
    
    # Create project creation script
    echo -e "${CYAN}📜 Creating project creation script...${NC}"
    cat > "scripts/new-${tech_name}-project.sh" << EOF
#!/bin/bash

# New $display_name Project Creation Script

PROJECT_NAME=\$1
TARGET_DIR=\$2

# Validate project name is provided
if [ -z "\$PROJECT_NAME" ]; then
    echo "Usage: ./new-${tech_name}-project.sh <project-name> [target-directory]"
    echo "Examples:"
    echo "  ./new-${tech_name}-project.sh myapp                    # Creates ~/projects/myapp"
    echo "  ./new-${tech_name}-project.sh myapp ../../MyProjects   # Creates ../../MyProjects/myapp"
    echo ""
    echo "This script will:"
    echo "  1. Create a new $display_name project"
    echo "  2. Copy DevContainer and VS Code configurations" 
    echo "  3. Set up project template"
    echo "  4. Initialize git repository"
    echo ""
    exit 1
fi

# If no target directory specified, default to ~/projects/<project-name>
if [ -z "\$TARGET_DIR" ]; then
    TARGET_DIR="\$HOME/projects"
    PROJECT_PATH="\$TARGET_DIR/\$PROJECT_NAME"
    
    # Check if project already exists
    if [ -d "\$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at \$PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
    
    # Create the target directory if it doesn't exist
    if [ ! -d "\$TARGET_DIR" ]; then
        echo "📁 Creating projects directory: \$TARGET_DIR"
        mkdir -p "\$TARGET_DIR"
    fi
else
    PROJECT_PATH="\$TARGET_DIR/\$PROJECT_NAME"
    
    # Check if project already exists in specified directory
    if [ -d "\$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at \$PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
fi

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="\$(dirname "\$SCRIPT_DIR")"
TEMPLATE_DIR="\$BENCH_DIR/templates/basic-project"

echo "📦 Creating $display_name project: \$PROJECT_NAME"
echo "📍 Project path: \$PROJECT_PATH"

# Create project directory
mkdir -p "\$PROJECT_PATH"
cd "\$PROJECT_PATH"

# Copy template if available
if [ -d "\$TEMPLATE_DIR" ]; then
    echo "📋 Copying project template..."
    cp -r "\$TEMPLATE_DIR"/* .
    cp -r "\$TEMPLATE_DIR"/.[^.]* . 2>/dev/null || true
else
    echo "📋 Creating basic project structure..."
    mkdir -p src tests docs
    
    # Create a basic main file
    echo "// $display_name Project: \$PROJECT_NAME" > src/main.${tech_name}
    echo "// Generated by WorkBenches" >> src/main.${tech_name}
    
    # Create basic README
    cat > README.md << EOL
# \$PROJECT_NAME

A $display_name project created with WorkBenches.

## Getting Started

1. Open this project in VS Code
2. Click "Reopen in Container" when prompted  
3. Start developing!

## Project Structure

- \`src/\` - Source code
- \`tests/\` - Test files
- \`docs/\` - Documentation

## Available Scripts

Add your project-specific scripts here.

## Contributing

Instructions for contributing to this project.
EOL
fi

# Copy DevContainer configuration
echo "📋 Copying DevContainer configuration..."
cp -r "\$BENCH_DIR/.devcontainer" .
cp -r "\$BENCH_DIR/.vscode" .

# Copy specKit from workBenches
echo "📋 Copying specKit for spec-driven development..."
WORKBENCHES_DIR="\$(dirname "\$(dirname "\$BENCH_DIR")")"
SPECKIT_SOURCE="\$WORKBENCHES_DIR/specKit"

if [ -d "\$SPECKIT_SOURCE" ]; then
    # Copy specKit contents (excluding .git)
    cp -r "\$SPECKIT_SOURCE"/* .
    cp -r "\$SPECKIT_SOURCE"/.[^.]* . 2>/dev/null || true  # Copy hidden files, ignore errors
    
    # Remove git-related files if they were copied
    rm -rf .git 2>/dev/null || true
    
    echo "✓ specKit copied successfully"
else
    echo "⚠️  Warning: specKit not found at \$SPECKIT_SOURCE"
    echo "   Run setup-workbenches.sh to install specKit"
fi

# Initialize git repository
echo "📦 Initializing git repository..."
git init
git add .
git commit -m "Initial commit - $display_name project created by WorkBenches"

# Create .gitignore additions
echo "" >> .gitignore
echo "# Project specific" >> .gitignore
echo "*.log" >> .gitignore
echo ".env" >> .gitignore

echo ""
echo "✅ Project created successfully: \$PROJECT_PATH"
echo ""
echo "📝 Next steps:"
echo "   1. cd \$PROJECT_PATH"
echo "   2. code ."
echo "   3. When prompted, click 'Reopen in Container'"
echo "   4. Start developing!"
echo ""
echo "📚 For spec-driven development: see README.md and spec-driven.md"
echo "📚 Use /constitution, /specify, /plan, /tasks, /implement commands"
echo ""
echo "🎯 Happy $display_name Development with Spec-Driven Development!"
EOF
    
    chmod +x "scripts/new-${tech_name}-project.sh"
    
    # Create basic project template
    echo -e "${CYAN}📁 Creating project template...${NC}"
    mkdir -p "templates/basic-project/src"
    
    case "$tech_name" in
        "go")
            echo 'package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}' > "templates/basic-project/src/main.go"
            ;;
        "rust")
            echo 'fn main() {
    println!("Hello, World!");
}' > "templates/basic-project/src/main.rs"
            ;;
        "node")
            echo 'console.log("Hello, World!");' > "templates/basic-project/src/main.js"
            ;;
        *)
            echo "// Hello, World! in $display_name" > "templates/basic-project/src/main.${tech_name}"
            ;;
    esac
    
    # Create documentation
    echo -e "${CYAN}📚 Creating documentation...${NC}"
    cat > docs/setup.md << EOF
# $display_name Bench Setup Guide

## Prerequisites

- Docker Desktop
- VS Code with Dev Containers extension
- Git

## Quick Setup

1. Clone this bench (if using remote repository)
2. Open in VS Code
3. Click "Reopen in Container"
4. Wait for setup to complete

## Manual Setup

If you prefer manual setup without containers:

1. Install $display_name
2. Install required tools: $(echo "$stack" | jq -r '.tools | join(", ")')
3. Run setup scripts

## Creating Projects

Use the WorkBenches unified interface:

\`\`\`bash
cd path/to/workBenches
./new-project.sh
\`\`\`

Or use the bench-specific script directly:

\`\`\`bash
./scripts/new-${tech_name}-project.sh <project-name>
\`\`\`

## Troubleshooting

### Container Issues
- Ensure Docker Desktop is running
- Try rebuilding the container: Cmd/Ctrl+Shift+P → "Dev Containers: Rebuild Container"

### Permission Issues
- Check file permissions in the container
- Ensure proper user mapping in devcontainer.json

## Advanced Configuration

You can customize this bench by:
- Modifying \`.devcontainer/devcontainer.json\`
- Adding VS Code extensions in the configuration
- Creating custom project templates in \`templates/\`
- Adding automation scripts in \`scripts/\`
EOF
    
    # Add and commit all files
    echo -e "${CYAN}📦 Committing initial files...${NC}"
    git add .
    git commit -m "Initial bench setup for $display_name development"
    
    echo ""
    echo -e "${GREEN}✅ Bench created successfully!${NC}"
    echo ""
    echo -e "${BLUE}📦 Created: $display_name Development Bench${NC}"
    echo -e "${BLUE}📍 Location: $bench_path${NC}"
    echo -e "${BLUE}🔧 Project Script: scripts/new-${tech_name}-project.sh${NC}"
    echo ""
    
    # Update bench-config.json
    update_bench_config "$bench_path" "$stack" "$repo_url"
}

# Update bench-config.json with new bench
update_bench_config() {
    local bench_path="$1"
    local stack="$2"
    local repo_url="$3"
    
    local tech_name=$(echo "$stack" | jq -r '.name')
    local display_name=$(echo "$stack" | jq -r '.display_name')
    local description=$(echo "$stack" | jq -r '.description')
    local bench_name=$(basename "$bench_path")
    
    echo -e "${CYAN}📝 Updating bench-config.json...${NC}"
    
    # Create new bench entry
    local new_bench_entry="{
        \"url\": \"$repo_url\",
        \"path\": \"$bench_path\",
        \"description\": \"$description\",
        \"project_scripts\": [
            {
                \"name\": \"$tech_name\",
                \"script\": \"scripts/new-${tech_name}-project.sh\",
                \"description\": \"Create a new $display_name project with DevContainer setup\",
                \"includes_speckit\": true
            }
        ]
    }"
    
    # Update config file
    local updated_config=$(jq --arg key "$bench_name" --argjson value "$new_bench_entry" '.benches[$key] = $value' "$CONFIG_FILE")
    echo "$updated_config" > "$CONFIG_FILE"
    
    echo -e "${GREEN}✓ Configuration updated${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Test the bench: cd $bench_path && code ."
    echo "2. Create projects: ./new-project.sh"
    echo "3. Push to remote: git push origin main (if using remote repository)"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "This script creates new development benches with AI-powered tech stack discovery."
    echo ""
    echo "Environment Variables:"
    echo "  OPENAI_API_KEY      - OpenAI API key for tech stack discovery"
    echo "  ANTHROPIC_API_KEY   - Claude API key for tech stack discovery"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive mode with AI discovery"
    echo "  OPENAI_API_KEY=xxx $0 # Use OpenAI for current tech info"
    echo ""
    echo "The script will:"
    echo "  1. Query AI for current tech stacks (if API keys available)"
    echo "  2. Show interactive menu of technologies"
    echo "  3. Create complete bench structure with DevContainer"
    echo "  4. Generate project creation scripts"
    echo "  5. Update workBenches configuration"
}

# Main function
main() {
    echo -e "${BLUE}WorkBenches New Bench Creation Script${NC}"
    echo "====================================="
    echo ""
    
    # Check for help flag
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    check_dependencies
    
    # Load configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
        echo "Run ./setup-workbenches.sh first to initialize workBenches."
        exit 1
    fi
    
    echo -e "${YELLOW}This script will help you create a new development bench.${NC}"
    echo "A bench provides a complete development environment for a specific technology."
    echo ""
    
    # Check for AI API keys
    if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
        echo -e "${GREEN}🤖 AI API keys detected - will get current tech stack info${NC}"
    else
        echo -e "${YELLOW}⚠️  No AI API keys found - using built-in tech stack list${NC}"
        echo "   Set OPENAI_API_KEY or ANTHROPIC_API_KEY for current information"
    fi
    echo ""
    
    # Get tech stack information
    local tech_stacks
    tech_stacks=$(get_ai_tech_stacks)
    
    # Show available stacks
    show_tech_stacks "$tech_stacks"
    
    # Let user select
    select_tech_stack "$tech_stacks"
    
    echo ""
    echo -e "${GREEN}🎉 New bench creation completed!${NC}"
    echo ""
    echo "Your new bench is ready for development. You can now:"
    echo "• Open it in VS Code with DevContainer support"
    echo "• Create new projects using the WorkBenches unified interface"
    echo "• Customize the bench configuration and templates"
}

# Run main function
main "$@"